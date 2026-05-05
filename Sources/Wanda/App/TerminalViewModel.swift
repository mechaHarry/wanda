import Foundation
import SwiftUI

@MainActor
public final class TerminalViewModel: ObservableObject {
    @Published public private(set) var snapshot: TerminalRendererSnapshot?
    @Published public private(set) var statusMessage: String?

    private static let maxPendingLatencyIDs = 128

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
        self.init(columns: columns, rows: rows, scrollbackLimit: scrollbackLimit, pty: nil)
    }

    init(columns: Int, rows: Int, scrollbackLimit: Int, pty: (any PseudoTerminal)?) {
        self.parser = SwiftTerminalParser()
        self.model = TerminalModel(columns: columns, rows: rows, scrollbackLimit: scrollbackLimit)
        self.latencyProbe = LatencyProbe()
        self.keyMapper = TerminalKeyMapper()
        self.pty = pty
        self.snapshot = TerminalRendererSnapshot(model: model)
    }

    public func startDefaultShell() {
        if let pty {
            startOutputPumpIfNeeded(for: pty)
            return
        }

        let shell = defaultShellPath()
        let size = TerminalSize(
            columns: model.visibleGrid.columns,
            rows: model.visibleGrid.rows
        )

        do {
            let terminal = try PosixPseudoTerminal(
                executablePath: shell,
                arguments: [shell],
                environment: ["TERM": "xterm-256color"],
                size: size
            )
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
            for pendingLatencyID in pendingLatencyIDs {
                latencyProbe.recordModelMutation(for: pendingLatencyID)
            }
        }

        snapshot = TerminalRendererSnapshot(model: model)
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
        snapshot = TerminalRendererSnapshot(model: model)
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

    private func startOutputPumpIfNeeded(for terminal: any PseudoTerminal) {
        guard outputTask == nil else {
            return
        }

        nextOutputTaskID += 1
        let taskID = nextOutputTaskID
        outputTaskID = taskID
        outputTask = Task.detached(priority: .userInitiated) { [weak self, terminal] in
            while !Task.isCancelled {
                guard self != nil else {
                    break
                }

                var drainedBytes: [UInt8] = []
                var pendingError: Error?

                while !Task.isCancelled {
                    do {
                        let bytes = try terminal.readAvailableBytes(maxBytes: 4096)

                        if bytes.isEmpty {
                            break
                        }

                        drainedBytes.append(contentsOf: bytes)
                    } catch is CancellationError {
                        pendingError = nil
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

                if let pendingError {
                    guard !Task.isCancelled else {
                        break
                    }

                    let message = "Failed to read from terminal: \(pendingError)"
                    await MainActor.run { [weak self] in
                        self?.statusMessage = message
                    }
                    break
                }

                if terminal.state != .running {
                    break
                }

                do {
                    try await Task.sleep(nanoseconds: 5_000_000)
                } catch {
                    break
                }
            }

            await MainActor.run { [weak self] in
                self?.finishOutputPump(id: taskID)
            }
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

    private func defaultShellPath() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"]
        guard let shell, !shell.isEmpty else {
            return "/bin/zsh"
        }

        return shell
    }
}
