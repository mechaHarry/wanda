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
        case osc(byteCount: Int)
        case oscEscape(byteCount: Int)
        case discardOSC
        case utf8(bytes: [UInt8], expectedLength: Int)
    }

    private var state: State = .ground
    private let maxParameterDigits: Int
    private let maxCSIBufferLength: Int
    private let maxOSCBufferLength: Int

    public init(maxParameterDigits: Int = 8, maxCSIBufferLength: Int = 64, maxOSCBufferLength: Int = 4_096) {
        self.maxParameterDigits = maxParameterDigits
        self.maxCSIBufferLength = maxCSIBufferLength
        self.maxOSCBufferLength = maxOSCBufferLength
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
            case .osc(let byteCount):
                parseOSC(byte, byteCount: byteCount)
            case .oscEscape(let byteCount):
                parseOSCEscape(byte, byteCount: byteCount)
            case .discardOSC:
                discardOSC(byte)
            case .utf8(let bytes, let expectedLength):
                parseUTF8(byte, bytes: bytes, expectedLength: expectedLength, events: &events)
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
        case 0xC2...0xDF:
            state = .utf8(bytes: [byte], expectedLength: 2)
        case 0xE0...0xEF:
            state = .utf8(bytes: [byte], expectedLength: 3)
        case 0xF0...0xF4:
            state = .utf8(bytes: [byte], expectedLength: 4)
        default:
            break
        }
    }

    private mutating func parseUTF8(
        _ byte: UInt8,
        bytes: [UInt8],
        expectedLength: Int,
        events: inout [TerminalEvent]
    ) {
        guard byte >= 0x80 && byte <= 0xBF else {
            events.append(.malformedSequence)
            state = .ground
            parseGround(byte, events: &events)
            return
        }

        let nextBytes = bytes + [byte]
        guard nextBytes.count == expectedLength else {
            state = .utf8(bytes: nextBytes, expectedLength: expectedLength)
            return
        }

        if let string = String(bytes: nextBytes, encoding: .utf8),
           string.count == 1,
           let character = string.first {
            events.append(.print(character))
        } else {
            events.append(.malformedSequence)
        }
        state = .ground
    }

    private mutating func parseEscape(_ byte: UInt8, events: inout [TerminalEvent]) {
        if byte == UInt8(ascii: "[") {
            state = .csi("")
        } else if byte == UInt8(ascii: "]") {
            state = .osc(byteCount: 0)
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
            if buffer.count + 1 > maxCSIBufferLength {
                events.append(.malformedSequence)
                state = .discardCSI
                return
            }

            let digitCount = currentParameterDigitCount(in: buffer) + (character.isNumber ? 1 : 0)

            if digitCount > maxParameterDigits {
                events.append(.malformedSequence)
                state = .discardCSI
                return
            }

            state = .csi(buffer + String(character))
            return
        }

        let parameters = parseParameters(buffer)
        switch byte {
        case UInt8(ascii: "H"), UInt8(ascii: "f"):
            let row = max(cursorParameter(parameters, at: 0) - 1, 0)
            let column = max(cursorParameter(parameters, at: 1) - 1, 0)
            events.append(.moveCursor(row: row, column: column))
        case UInt8(ascii: "A"):
            events.append(.cursorUp(movementParameter(parameters)))
        case UInt8(ascii: "B"):
            events.append(.cursorDown(movementParameter(parameters)))
        case UInt8(ascii: "C"):
            events.append(.cursorForward(movementParameter(parameters)))
        case UInt8(ascii: "D"):
            events.append(.cursorBackward(movementParameter(parameters)))
        case UInt8(ascii: "G"):
            let column = max(cursorParameter(parameters, at: 0) - 1, 0)
            events.append(.cursorHorizontalAbsolute(column: column))
        case UInt8(ascii: "J"):
            switch parameters.first ?? 0 {
            case 0:
                events.append(.eraseScreen(.cursorToEnd))
            case 1:
                events.append(.eraseScreen(.startToCursor))
            case 2:
                events.append(.eraseScreen(.all))
            default:
                events.append(.malformedSequence)
            }
        case UInt8(ascii: "K"):
            switch parameters.first ?? 0 {
            case 0:
                events.append(.eraseLine(.cursorToEnd))
            case 1:
                events.append(.eraseLine(.startToCursor))
            case 2:
                events.append(.eraseLine(.all))
            default:
                events.append(.malformedSequence)
            }
        case UInt8(ascii: "m"):
            events.append(.setGraphicRendition(parameters))
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

    private mutating func parseOSC(_ byte: UInt8, byteCount: Int) {
        switch byte {
        case 0x07:
            state = .ground
        case 0x1B:
            state = .oscEscape(byteCount: byteCount)
        default:
            let nextByteCount = byteCount + 1
            state = nextByteCount > maxOSCBufferLength ? .discardOSC : .osc(byteCount: nextByteCount)
        }
    }

    private mutating func parseOSCEscape(_ byte: UInt8, byteCount: Int) {
        if byte == UInt8(ascii: "\\") {
            state = .ground
            return
        }

        let nextByteCount = byteCount + 2
        state = nextByteCount > maxOSCBufferLength ? .discardOSC : .osc(byteCount: nextByteCount)
    }

    private mutating func discardOSC(_ byte: UInt8) {
        switch byte {
        case 0x07:
            state = .ground
        case 0x1B:
            state = .oscEscape(byteCount: maxOSCBufferLength)
        default:
            break
        }
    }

    private func currentParameterDigitCount(in buffer: String) -> Int {
        buffer.reversed().prefix { $0.isNumber }.count
    }

    private func parseParameters(_ buffer: String) -> [Int] {
        let parameters = buffer.components(separatedBy: ";").map { Int($0) ?? 0 }
        return parameters.isEmpty ? [0] : parameters
    }

    private func cursorParameter(_ parameters: [Int], at index: Int) -> Int {
        guard index < parameters.count else {
            return 1
        }
        return parameters[index] == 0 ? 1 : parameters[index]
    }

    private func movementParameter(_ parameters: [Int]) -> Int {
        max(parameters.first ?? 1, 1)
    }
}
