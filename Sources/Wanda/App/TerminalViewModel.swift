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
        guard pty == nil else {
            return
        }

        let shell = defaultShellPath()
        let size = TerminalSize(
            columns: model.visibleGrid.columns,
            rows: model.visibleGrid.rows
        )

        do {
            pty = try PosixPseudoTerminal(
                executablePath: shell,
                arguments: [shell],
                environment: ["TERM": "xterm-256color"],
                size: size
            )
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

    public nonisolated func framePresented(at timestamp: UInt64) {
        Task { @MainActor [weak self] in
            self?.recordFramePresented(at: timestamp)
        }
    }

    public func stop() {
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
