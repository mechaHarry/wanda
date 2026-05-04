import Foundation

public struct TerminalPoint: Equatable, Hashable, Sendable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

public enum TerminalColor: Equatable, Sendable {
    case `default`
    case ansi(index: UInt8)
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
}

public struct TerminalAttributes: Equatable, Sendable {
    public var foreground: TerminalColor
    public var background: TerminalColor
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderline: Bool
    public var isInverse: Bool

    public init(
        foreground: TerminalColor = .default,
        background: TerminalColor = .default,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        isInverse: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.isInverse = isInverse
    }
}

public struct TerminalCell: Equatable, Sendable {
    public var character: Character
    public var attributes: TerminalAttributes

    public init(character: Character = " ", attributes: TerminalAttributes = TerminalAttributes()) {
        self.character = character
        self.attributes = attributes
    }

    public static let blank = TerminalCell()
}
