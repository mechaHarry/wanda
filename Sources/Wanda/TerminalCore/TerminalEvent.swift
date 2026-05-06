import Foundation

public enum TerminalEvent: Equatable, Sendable {
    case print(Character)
    case moveCursor(row: Int, column: Int)
    case cursorUp(Int)
    case cursorDown(Int)
    case cursorForward(Int)
    case cursorBackward(Int)
    case carriageReturn
    case lineFeed
    case backspace
    case eraseScreen(TerminalEraseMode)
    case clearLine
    case setGraphicRendition([Int])
    case useAlternateScreen(Bool)
    case malformedSequence
}

public enum TerminalEraseMode: Equatable, Sendable {
    case cursorToEnd
    case startToCursor
    case all
}
