import XCTest
@testable import Wanda

final class TerminalKeyMapperTests: XCTestCase {
    func testPrintableCharacterMapsToUTF8Bytes() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .printable("a")), Array("a".utf8))
    }

    func testOptionLeftMapsToEscapeB() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .special(.leftArrow, modifiers: [.option])), [0x1B, UInt8(ascii: "b")])
    }

    func testOptionRightMapsToEscapeF() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .special(.rightArrow, modifiers: [.option])), [0x1B, UInt8(ascii: "f")])
    }

    func testCommandLeftAndRightMapToLineBoundaries() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .special(.leftArrow, modifiers: [.command])), [0x01])
        XCTAssertEqual(mapper.bytes(for: .special(.rightArrow, modifiers: [.command])), [0x05])
    }

    func testPlainArrowsMapToEscapeSequences() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .special(.leftArrow, modifiers: [])), Array("\u{001B}[D".utf8))
        XCTAssertEqual(mapper.bytes(for: .special(.rightArrow, modifiers: [])), Array("\u{001B}[C".utf8))
        XCTAssertEqual(mapper.bytes(for: .special(.upArrow, modifiers: [])), Array("\u{001B}[A".utf8))
        XCTAssertEqual(mapper.bytes(for: .special(.downArrow, modifiers: [])), Array("\u{001B}[B".utf8))
    }

    func testReturnDeleteAndTabMapToControlBytes() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .special(.returnKey, modifiers: [])), [0x0D])
        XCTAssertEqual(mapper.bytes(for: .special(.delete, modifiers: [])), [0x7F])
        XCTAssertEqual(mapper.bytes(for: .special(.tab, modifiers: [])), [0x09])
    }

    func testOptionTakesPrecedenceOverCommandForCombinedLeftArrowModifier() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .special(.leftArrow, modifiers: [.option, .command])), [0x1B, UInt8(ascii: "b")])
    }
}
