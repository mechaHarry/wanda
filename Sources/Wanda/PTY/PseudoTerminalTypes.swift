import Foundation

struct TerminalSize: Equatable, Sendable {
    var columns: UInt16
    var rows: UInt16

    init(columns: UInt16, rows: UInt16) {
        self.columns = columns
        self.rows = rows
    }
}

enum PseudoTerminalState: Equatable, Sendable {
    case running
    case terminated
}

enum PseudoTerminalError: Error, Equatable, Sendable {
    case openFailed(errno: Int32)
    case forkFailed(errno: Int32)
    case configureFailed(errno: Int32)
    case writeFailed(errno: Int32)
    case readFailed(errno: Int32)
    case resizeFailed(errno: Int32)
    case processTerminated
    case timedOut
    case invalidOutputEncoding
}
