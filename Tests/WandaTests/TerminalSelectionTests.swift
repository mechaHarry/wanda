import XCTest
@testable import Wanda

final class TerminalSelectionTests: XCTestCase {
    func testLinearSelectionCopiesAcrossCells() {
        var grid = TerminalGrid(columns: 5, rows: 2)
        for (index, character) in Array("hello").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 0))
        }
        for (index, character) in Array("world").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 1))
        }

        let selection = TerminalSelection(start: TerminalPoint(column: 1, row: 0), end: TerminalPoint(column: 2, row: 1))

        XCTAssertEqual(selection.string(in: grid), "ello\nwor")
    }

    func testReversedLinearSelectionCopiesSameText() {
        var grid = TerminalGrid(columns: 5, rows: 2)
        for (index, character) in Array("hello").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 0))
        }
        for (index, character) in Array("world").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 1))
        }

        let selection = TerminalSelection(start: TerminalPoint(column: 2, row: 1), end: TerminalPoint(column: 1, row: 0))

        XCTAssertEqual(selection.string(in: grid), "ello\nwor")
    }

    func testSelectionTrimsTrailingSpacesPerRow() {
        var grid = TerminalGrid(columns: 6, rows: 2)
        for (index, character) in Array("hi").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 0))
        }
        for (index, character) in Array("ok").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 1))
        }

        let selection = TerminalSelection(start: TerminalPoint(column: 0, row: 0), end: TerminalPoint(column: 5, row: 1))

        XCTAssertEqual(selection.string(in: grid), "hi\nok")
    }

    func testDoubleClickTokenKeepsURLCharacters() {
        var grid = TerminalGrid(columns: 40, rows: 1)
        let text = "open https://example.com/a-b?q=1 now"
        for (index, character) in Array(text).enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 0))
        }

        let token = TerminalSelection.token(at: TerminalPoint(column: 14, row: 0), in: grid)

        XCTAssertEqual(token.string(in: grid), "https://example.com/a-b?q=1")
    }

    func testDoubleClickTokenStopsAtWhitespace() {
        var grid = TerminalGrid(columns: 20, rows: 1)
        for (index, character) in Array("alpha beta").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 0))
        }

        let token = TerminalSelection.token(at: TerminalPoint(column: 7, row: 0), in: grid)

        XCTAssertEqual(token.string(in: grid), "beta")
    }

    func testDoubleClickTokenOnDelimiterDoesNotCrossDelimiter() {
        var grid = TerminalGrid(columns: 20, rows: 1)
        for (index, character) in Array("alpha(beta").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 0))
        }

        let token = TerminalSelection.token(at: TerminalPoint(column: 5, row: 0), in: grid)

        XCTAssertEqual(token.string(in: grid), "(")
    }
}
