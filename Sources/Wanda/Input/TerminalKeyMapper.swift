import Foundation

public struct TerminalKeyMapper: Sendable {
    public init() {}

    public func bytes(for event: TerminalKeyEvent) -> [UInt8] {
        switch event {
        case .printable(let string):
            return Array(string.utf8)
        case .special(let key, let modifiers):
            return bytes(for: key, modifiers: modifiers)
        }
    }

    private func bytes(for key: TerminalSpecialKey, modifiers: TerminalKeyModifiers) -> [UInt8] {
        if key == .leftArrow && modifiers.contains(.option) {
            return [0x1B, UInt8(ascii: "b")]
        }
        if key == .rightArrow && modifiers.contains(.option) {
            return [0x1B, UInt8(ascii: "f")]
        }
        if key == .leftArrow && modifiers.contains(.command) {
            return [0x01]
        }
        if key == .rightArrow && modifiers.contains(.command) {
            return [0x05]
        }

        switch key {
        case .leftArrow:
            return Array("\u{001B}[D".utf8)
        case .rightArrow:
            return Array("\u{001B}[C".utf8)
        case .upArrow:
            return Array("\u{001B}[A".utf8)
        case .downArrow:
            return Array("\u{001B}[B".utf8)
        case .returnKey:
            return [0x0D]
        case .delete:
            return [0x7F]
        case .tab:
            return [0x09]
        }
    }
}
