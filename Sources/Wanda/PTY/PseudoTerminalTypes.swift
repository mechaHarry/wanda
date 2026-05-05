import Foundation

public struct TerminalSize: Equatable, Sendable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        precondition(columns > 0, "Terminal columns must be positive")
        precondition(rows > 0, "Terminal rows must be positive")
        self.columns = columns
        self.rows = rows
    }
}

public enum PseudoTerminalState: Equatable, Sendable {
    case running
    case terminating
    case exited(Int32)
    case failed(String)
}

public enum PseudoTerminalError: Error, Equatable {
    case openFailed
    case forkFailed
    case execFailed
    case writeFailed(Int32)
    case readFailed(Int32)
    case resizeFailed(Int32)
    case timedOut
}
