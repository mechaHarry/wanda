import Foundation
import SwiftUI

@MainActor
public final class TerminalViewModel: ObservableObject {
    typealias TerminalFactory = @MainActor (
        _ executablePath: String,
        _ arguments: [String],
        _ environment: [String: String],
        _ size: TerminalSize
    ) throws -> any PseudoTerminal

    @Published public private(set) var snapshot: TerminalRendererSnapshot?
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var selection: TerminalSelection?

    private static let maxPendingLatencyIDs = 128
    private static let maxOutputBatchBytes = 64 * 1024
    private static let outputPumpReadMaxBytes = 4_096
    private static let terminatingReapAttemptCount = 20
    private static let terminatingReapSleepNanoseconds: UInt64 = 5_000_000

    private var parser: any TerminalParser
    private var model: TerminalModel
    private var latencyProbe: LatencyProbe
    private let keyMapper: TerminalKeyMapper
    private var pendingLatencyIDs: [Int] = []
    private var pty: (any PseudoTerminal)?
    private var outputTask: Task<Void, Never>?
    private var outputTaskID: Int?
    private var nextOutputTaskID = 0
    private var outputPumpBatchCount = 0
    private var scrollbackOffsetRows = 0
    private let environment: [String: String]
    private let terminalFactory: TerminalFactory

    var debugActiveLatencyCount: Int {
        latencyProbe.activeMeasurementCount
    }

    var debugPendingLatencyCount: Int {
        pendingLatencyIDs.count
    }

    var debugCompletedLatencyCount: Int {
        latencyProbe.completedMeasurements.count
    }

    var debugCompletedLatencyMeasurements: [LatencyMeasurement] {
        latencyProbe.completedMeasurements
    }

    var debugHasOutputTask: Bool {
        outputTask != nil
    }

    var debugOutputPumpBatchCount: Int {
        outputPumpBatchCount
    }

    public convenience init(columns: Int = 80, rows: Int = 24, scrollbackLimit: Int = 2_000) {
        self.init(
            columns: columns,
            rows: rows,
            scrollbackLimit: scrollbackLimit,
            pty: nil,
            environment: ProcessInfo.processInfo.environment,
            terminalFactory: Self.makePosixPseudoTerminal
        )
    }

    init(
        columns: Int,
        rows: Int,
        scrollbackLimit: Int,
        pty: (any PseudoTerminal)?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        terminalFactory: @escaping TerminalFactory = TerminalViewModel.makePosixPseudoTerminal
    ) {
        self.parser = SwiftTerminalParser()
        self.model = TerminalModel(columns: columns, rows: rows, scrollbackLimit: scrollbackLimit)
        self.latencyProbe = LatencyProbe()
        self.keyMapper = TerminalKeyMapper()
        self.pty = pty
        self.environment = environment
        self.terminalFactory = terminalFactory
        self.snapshot = TerminalRendererSnapshot(model: model)
    }

    public func startDefaultShell() {
        if let pty {
            startOutputPumpIfNeeded(for: pty)
            return
        }

        var environment = environment
        environment["TERM"] = "xterm-256color"
        let shell = defaultShellPath(environment: environment)
        let size = TerminalSize(
            columns: model.visibleGrid.columns,
            rows: model.visibleGrid.rows
        )

        do {
            let terminal = try terminalFactory(shell, [shell], environment, size)
            pty = terminal
            startOutputPumpIfNeeded(for: terminal)
            statusMessage = nil
        } catch {
            statusMessage = "Failed to start shell: \(error)"
        }
    }

    public func processOutput(_ bytes: [UInt8]) {
        let events = parser.parse(bytes)

        for event in events {
            model.apply(event)
        }

        if !events.isEmpty {
            scrollbackOffsetRows = 0
            for pendingLatencyID in pendingLatencyIDs {
                latencyProbe.recordModelMutation(for: pendingLatencyID)
            }
        }

        refreshSnapshot()
    }

    public func beginSelection(at point: TerminalPoint) {
        let point = clampedPoint(point)
        selection = TerminalSelection(start: point, end: point)
    }

    public func updateSelection(to point: TerminalPoint) {
        let point = clampedPoint(point)
        guard let selection else {
            beginSelection(at: point)
            return
        }

        self.selection = TerminalSelection(start: selection.start, end: point)
    }

    public func selectToken(at point: TerminalPoint) {
        selection = TerminalSelection.token(at: clampedPoint(point), in: model.visibleGrid)
    }

    public func clearSelection() {
        selection = nil
    }

    public func scrollOutput(byRows rows: Int) {
        guard rows != 0, !model.isUsingAlternateScreen else {
            return
        }

        scrollbackOffsetRows = min(max(scrollbackOffsetRows + rows, 0), model.scrollback.count)
        clearSelection()
        refreshSnapshot(forceDirty: true)
    }

    public func selectedText() -> String? {
        selection?.string(in: model.visibleGrid)
    }

    public func handleKey(_ event: TerminalKeyEvent) {
        let bytes = keyMapper.bytes(for: event)
        guard let pty else {
            return
        }

        let latencyID = latencyProbe.recordKeyReceived()
        do {
            try pty.write(bytes)
            latencyProbe.recordPTYWrite(for: latencyID)
            enqueuePendingLatencyID(latencyID)
        } catch {
            latencyProbe.cancel(latencyID)
            statusMessage = "Failed to write to terminal: \(error)"
        }
    }

    public func resize(columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else {
            return
        }

        do {
            try pty?.resize(TerminalSize(columns: columns, rows: rows))
        } catch {
            statusMessage = "Failed to resize terminal: \(error)"
            return
        }

        model.resize(columns: columns, rows: rows)
        scrollbackOffsetRows = 0
        refreshSnapshot()
    }

    public nonisolated func framePresented(at timestamp: UInt64) {
        Task { @MainActor [weak self] in
            self?.recordFramePresented(at: timestamp)
        }
    }

    public func stop() {
        outputTask?.cancel()
        outputTask = nil
        outputTaskID = nil
        pty?.terminate()
        pty = nil
        cancelPendingLatencyIDs()
    }

    private func recordFramePresented(at timestamp: UInt64) {
        guard !pendingLatencyIDs.isEmpty else {
            return
        }

        let pendingLatencyID = pendingLatencyIDs.removeFirst()
        latencyProbe.recordFramePresented(for: pendingLatencyID, at: timestamp)
    }

    private func refreshSnapshot(forceDirty: Bool = false) {
        var nextSnapshot = TerminalRendererSnapshot(model: model, scrollbackOffsetRows: scrollbackOffsetRows)
        if forceDirty {
            nextSnapshot.dirtyRows = Set(0..<nextSnapshot.rows)
        }
        snapshot = nextSnapshot
    }

    private func startOutputPumpIfNeeded(for terminal: any PseudoTerminal) {
        guard outputTask == nil else {
            return
        }

        nextOutputTaskID += 1
        let taskID = nextOutputTaskID
        let maxOutputBatchBytes = Self.maxOutputBatchBytes
        let outputPumpReadMaxBytes = Self.outputPumpReadMaxBytes
        let terminatingReapAttemptCount = Self.terminatingReapAttemptCount
        let terminatingReapSleepNanoseconds = Self.terminatingReapSleepNanoseconds
        outputTaskID = taskID
        outputTask = Task.detached(priority: .userInitiated) { [weak self, terminal] in
            pumpLoop: while !Task.isCancelled {
                guard self != nil else {
                    break
                }

                var drainedBytes: [UInt8] = []
                var pendingError: Error?
                var shouldSleepAfterBatch = false
                var shouldStop = false

                while !Task.isCancelled {
                    do {
                        let bytes = try terminal.readAvailableBytes(maxBytes: outputPumpReadMaxBytes)

                        if bytes.isEmpty {
                            shouldSleepAfterBatch = true
                            break
                        }

                        drainedBytes.append(contentsOf: bytes)

                        if drainedBytes.count >= maxOutputBatchBytes {
                            break
                        }
                    } catch is CancellationError {
                        shouldStop = true
                        break
                    } catch {
                        pendingError = error
                        break
                    }
                }

                if !drainedBytes.isEmpty {
                    if Task.isCancelled {
                        break
                    }

                    await MainActor.run { [weak self] in
                        guard !Task.isCancelled else {
                            return
                        }
                        self?.processOutput(drainedBytes)
                        self?.outputPumpBatchCount += 1
                    }
                }

                if shouldStop || Task.isCancelled {
                    break pumpLoop
                }

                if let pendingError {
                    guard !Task.isCancelled else {
                        break pumpLoop
                    }

                    let message = "Failed to read from terminal: \(pendingError)"
                    await MainActor.run { [weak self] in
                        self?.statusMessage = message
                    }
                    break pumpLoop
                }

                switch terminal.state {
                case .running:
                    break
                case .terminating:
                    let terminatingResult = await driveTerminatingOutputPump(
                        terminal: terminal,
                        maxBytes: outputPumpReadMaxBytes,
                        attemptCount: terminatingReapAttemptCount,
                        sleepNanoseconds: terminatingReapSleepNanoseconds
                    )

                    switch terminatingResult {
                    case .running:
                        continue pumpLoop
                    case .finished:
                        let state = terminal.state
                        await MainActor.run { [weak self] in
                            self?.reportTerminalCompletion(state)
                        }
                        break pumpLoop
                    case .cancelled:
                        break pumpLoop
                    case .timedOut:
                        terminal.terminate()
                        break pumpLoop
                    case .failed(let error):
                        guard !Task.isCancelled else {
                            break pumpLoop
                        }

                        let message = "Failed to read from terminal: \(error)"
                        await MainActor.run { [weak self] in
                            self?.statusMessage = message
                        }
                        break pumpLoop
                    }
                case .exited(let status):
                    await MainActor.run { [weak self] in
                        self?.reportTerminalCompletion(.exited(status))
                    }
                    break pumpLoop
                case .signaled(let signal):
                    await MainActor.run { [weak self] in
                        self?.reportTerminalCompletion(.signaled(signal))
                    }
                    break pumpLoop
                case .failed(let reason):
                    await MainActor.run { [weak self] in
                        self?.reportTerminalCompletion(.failed(reason))
                    }
                    break pumpLoop
                }

                if shouldSleepAfterBatch {
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000)
                    } catch {
                        break pumpLoop
                    }
                }
            }

            await MainActor.run { [weak self] in
                self?.finishOutputPump(id: taskID)
            }
        }
    }

    private func reportTerminalCompletion(_ state: PseudoTerminalState) {
        switch state {
        case .running, .terminating:
            break
        case .exited(let status):
            statusMessage = "Shell exited with status \(status)."
        case .signaled(let signal):
            statusMessage = "Shell terminated by signal \(signal)."
        case .failed(let reason):
            statusMessage = "Shell failed: \(reason)."
        }
    }

    private func finishOutputPump(id: Int) {
        guard outputTaskID == id else {
            return
        }

        outputTask = nil
        outputTaskID = nil
    }

    private func enqueuePendingLatencyID(_ id: Int) {
        pendingLatencyIDs.append(id)

        while pendingLatencyIDs.count > Self.maxPendingLatencyIDs {
            let droppedID = pendingLatencyIDs.removeFirst()
            latencyProbe.cancel(droppedID)
        }
    }

    private func cancelPendingLatencyIDs() {
        for pendingLatencyID in pendingLatencyIDs {
            latencyProbe.cancel(pendingLatencyID)
        }
        pendingLatencyIDs.removeAll()
    }

    private func defaultShellPath(environment: [String: String]) -> String {
        let shell = environment["SHELL"]
        guard let shell, !shell.isEmpty else {
            return "/bin/zsh"
        }

        return shell
    }

    private static func makePosixPseudoTerminal(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        size: TerminalSize
    ) throws -> any PseudoTerminal {
        try PosixPseudoTerminal(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            size: size
        )
    }

    private func clampedPoint(_ point: TerminalPoint) -> TerminalPoint {
        let grid = model.visibleGrid
        return TerminalPoint(
            column: min(max(point.column, 0), grid.columns - 1),
            row: min(max(point.row, 0), grid.rows - 1)
        )
    }
}

private enum OutputPumpTerminatingResult {
    case running
    case finished
    case timedOut
    case cancelled
    case failed(any Error)
}

private func driveTerminatingOutputPump(
    terminal: any PseudoTerminal,
    maxBytes: Int,
    attemptCount: Int,
    sleepNanoseconds: UInt64
) async -> OutputPumpTerminatingResult {
    guard attemptCount > 0 else {
        return terminal.state == .terminating ? .timedOut : .finished
    }

    for attemptIndex in 0..<attemptCount {
        if Task.isCancelled {
            return .cancelled
        }

        do {
            _ = try terminal.readAvailableBytes(maxBytes: maxBytes)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(error)
        }

        if Task.isCancelled {
            return .cancelled
        }

        switch terminal.state {
        case .running:
            return .running
        case .exited, .signaled, .failed:
            return .finished
        case .terminating:
            if attemptIndex < attemptCount - 1 {
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    return .cancelled
                }
            }
        }
    }

    switch terminal.state {
    case .running:
        return .running
    case .exited, .signaled, .failed:
        return .finished
    case .terminating:
        return .timedOut
    }
}
