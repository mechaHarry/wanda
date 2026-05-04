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
}
