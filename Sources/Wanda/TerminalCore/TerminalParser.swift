import Foundation

public protocol TerminalParser: Sendable {
    mutating func parse(_ bytes: [UInt8]) -> [TerminalEvent]
}

public struct SwiftTerminalParser: TerminalParser {
    private enum State {
        case ground
        case escape
        case csi(String)
        case discardCSI
    }

    private var state: State = .ground
    private let maxParameterDigits: Int

    public init(maxParameterDigits: Int = 8) {
        self.maxParameterDigits = maxParameterDigits
    }

    public mutating func parse(_ bytes: [UInt8]) -> [TerminalEvent] {
        var events: [TerminalEvent] = []

        for byte in bytes {
            switch state {
            case .ground:
                parseGround(byte, events: &events)
            case .escape:
                parseEscape(byte, events: &events)
            case .csi(let buffer):
                parseCSI(byte, buffer: buffer, events: &events)
            case .discardCSI:
                discardCSI(byte)
            }
        }

        return events
    }

    private mutating func parseGround(_ byte: UInt8, events: inout [TerminalEvent]) {
        switch byte {
        case 0x08:
            events.append(.backspace)
        case 0x0A:
            events.append(.lineFeed)
        case 0x0D:
            events.append(.carriageReturn)
        case 0x1B:
            state = .escape
        case 0x20...0x7E:
            if let scalar = UnicodeScalar(Int(byte)) {
                events.append(.print(Character(scalar)))
            }
        default:
            break
        }
    }

    private mutating func parseEscape(_ byte: UInt8, events: inout [TerminalEvent]) {
        if byte == UInt8(ascii: "[") {
            state = .csi("")
        } else {
            events.append(.malformedSequence)
            state = .ground
        }
    }

    private mutating func parseCSI(_ byte: UInt8, buffer: String, events: inout [TerminalEvent]) {
        guard let scalar = UnicodeScalar(Int(byte)) else {
            events.append(.malformedSequence)
            state = .ground
            return
        }
        let character = Character(scalar)

        if byte >= 0x30 && byte <= 0x3F {
            let digitCount = buffer.reduce(0) { partial, char in
                char.isNumber ? partial + 1 : partial
            } + (character.isNumber ? 1 : 0)

            if digitCount > maxParameterDigits {
                events.append(.malformedSequence)
                state = .discardCSI
                return
            }

            state = .csi(buffer + String(character))
            return
        }

        let parameters = buffer.split(separator: ";").map { Int($0) ?? 0 }
        switch byte {
        case UInt8(ascii: "H"), UInt8(ascii: "f"):
            let row = max((parameters.first ?? 1) - 1, 0)
            let column = max((parameters.dropFirst().first ?? 1) - 1, 0)
            events.append(.moveCursor(row: row, column: column))
        case UInt8(ascii: "A"):
            events.append(.cursorUp(max(parameters.first ?? 1, 1)))
        case UInt8(ascii: "B"):
            events.append(.cursorDown(max(parameters.first ?? 1, 1)))
        case UInt8(ascii: "C"):
            events.append(.cursorForward(max(parameters.first ?? 1, 1)))
        case UInt8(ascii: "D"):
            events.append(.cursorBackward(max(parameters.first ?? 1, 1)))
        case UInt8(ascii: "J"):
            events.append(.clearScreen)
        case UInt8(ascii: "K"):
            events.append(.clearLine)
        case UInt8(ascii: "m"):
            events.append(.setGraphicRendition(parameters.isEmpty ? [0] : parameters))
        case UInt8(ascii: "h") where buffer == "?1049":
            events.append(.useAlternateScreen(true))
        case UInt8(ascii: "l") where buffer == "?1049":
            events.append(.useAlternateScreen(false))
        default:
            events.append(.malformedSequence)
        }
        state = .ground
    }

    private mutating func discardCSI(_ byte: UInt8) {
        if byte >= 0x40 && byte <= 0x7E {
            state = .ground
        }
    }
}
