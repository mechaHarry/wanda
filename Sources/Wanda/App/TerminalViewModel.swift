import Foundation
import SwiftUI

@MainActor
public final class TerminalViewModel: ObservableObject {
    @Published public private(set) var snapshot: TerminalRendererSnapshot?
    @Published public private(set) var statusMessage: String?

    private var parser: any TerminalParser
    private var model: TerminalModel
    private var latencyProbe: LatencyProbe
    private let keyMapper: TerminalKeyMapper
    private var pendingLatencyID: Int?
    private var pty: (any PseudoTerminal)?

    public init(columns: Int = 80, rows: Int = 24, scrollbackLimit: Int = 2_000) {
        self.parser = SwiftTerminalParser()
        self.model = TerminalModel(columns: columns, rows: rows, scrollbackLimit: scrollbackLimit)
        self.latencyProbe = LatencyProbe()
        self.keyMapper = TerminalKeyMapper()
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

        if let pendingLatencyID, !events.isEmpty {
            latencyProbe.recordModelMutation(for: pendingLatencyID)
        }

        snapshot = TerminalRendererSnapshot(model: model)
    }

    public func handleKey(_ event: TerminalKeyEvent) {
        let latencyID = latencyProbe.recordKeyReceived()
        pendingLatencyID = latencyID

        let bytes = keyMapper.bytes(for: event)
        guard let pty else {
            return
        }

        do {
            try pty.write(bytes)
            latencyProbe.recordPTYWrite(for: latencyID)
        } catch {
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
    }

    private func recordFramePresented(at timestamp: UInt64) {
        guard let pendingLatencyID else {
            return
        }

        latencyProbe.recordFramePresented(for: pendingLatencyID, at: timestamp)
        self.pendingLatencyID = nil
    }

    private func defaultShellPath() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"]
        guard let shell, !shell.isEmpty else {
            return "/bin/zsh"
        }

        return shell
    }
}
