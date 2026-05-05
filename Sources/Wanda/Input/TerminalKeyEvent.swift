import Foundation

public enum TerminalKeyEvent: Equatable, Sendable {
    case printable(String)
    case special(TerminalSpecialKey, modifiers: TerminalKeyModifiers)
}

public enum TerminalSpecialKey: Equatable, Sendable {
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case returnKey
    case delete
    case tab
}

public struct TerminalKeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let option = TerminalKeyModifiers(rawValue: 1 << 0)
    public static let command = TerminalKeyModifiers(rawValue: 1 << 1)
    public static let control = TerminalKeyModifiers(rawValue: 1 << 2)
    public static let shift = TerminalKeyModifiers(rawValue: 1 << 3)
}
