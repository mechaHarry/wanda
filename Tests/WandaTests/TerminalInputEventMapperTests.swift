import AppKit
import XCTest
@testable import Wanda

final class TerminalInputEventMapperTests: XCTestCase {
    func testArrowKeyMapsWithSupportedModifiers() {
        let event = TerminalInputEventMapper.map(
            keyCode: 123,
            characters: nil,
            modifierFlags: [.option, .command, .control, .shift]
        )

        XCTAssertEqual(event, .special(.leftArrow, modifiers: [.option, .command, .control, .shift]))
    }

    func testReturnDeleteAndTabMapToSpecialKeys() {
        XCTAssertEqual(
            TerminalInputEventMapper.map(keyCode: 36, characters: "\r", modifierFlags: []),
            .special(.returnKey, modifiers: [])
        )
        XCTAssertEqual(
            TerminalInputEventMapper.map(keyCode: 51, characters: "\u{7F}", modifierFlags: []),
            .special(.delete, modifiers: [])
        )
        XCTAssertEqual(
            TerminalInputEventMapper.map(keyCode: 48, characters: "\t", modifierFlags: []),
            .special(.tab, modifiers: [])
        )
    }

    func testPrintableCharactersMapToPrintableEvent() {
        XCTAssertEqual(
            TerminalInputEventMapper.map(keyCode: 0, characters: "a", modifierFlags: []),
            .printable("a")
        )
    }

    func testNilAndEmptyCharactersAreUnmappableForUnknownKeyCodes() {
        XCTAssertNil(TerminalInputEventMapper.map(keyCode: 0, characters: nil, modifierFlags: []))
        XCTAssertNil(TerminalInputEventMapper.map(keyCode: 0, characters: "", modifierFlags: []))
    }
}
