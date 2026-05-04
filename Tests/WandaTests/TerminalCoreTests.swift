import XCTest
@testable import Wanda

final class TerminalCoreTests: XCTestCase {
    func testGridStartsBlankWithRequestedSize() {
        let grid = TerminalGrid(columns: 4, rows: 2)

        XCTAssertEqual(grid.columns, 4)
        XCTAssertEqual(grid.rows, 2)
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 0, row: 0)).character, " ")
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 3, row: 1)).character, " ")
    }

    func testSetCellStoresCharacterAndAttributes() {
        var grid = TerminalGrid(columns: 3, rows: 1)
        let attrs = TerminalAttributes(foreground: .ansi(index: 2), background: .ansi(index: 0), isBold: true)

        grid.setCell(TerminalCell(character: "A", attributes: attrs), at: TerminalPoint(column: 1, row: 0))

        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 1, row: 0)).character, "A")
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 1, row: 0)).attributes, attrs)
    }

    func testClearLineResetsEveryCellOnRow() {
        var grid = TerminalGrid(columns: 3, rows: 2)
        grid.setCell(TerminalCell(character: "X"), at: TerminalPoint(column: 0, row: 1))
        grid.setCell(TerminalCell(character: "Y"), at: TerminalPoint(column: 2, row: 1))

        grid.clearLine(row: 1)

        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 0, row: 1)), .blank)
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 2, row: 1)), .blank)
    }

    func testClearAllResetsEveryPopulatedCell() {
        var grid = TerminalGrid(columns: 2, rows: 2)
        grid.setCell(TerminalCell(character: "A"), at: TerminalPoint(column: 0, row: 0))
        grid.setCell(TerminalCell(character: "B"), at: TerminalPoint(column: 1, row: 0))
        grid.setCell(TerminalCell(character: "C"), at: TerminalPoint(column: 0, row: 1))
        grid.setCell(TerminalCell(character: "D"), at: TerminalPoint(column: 1, row: 1))

        grid.clearAll()

        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 0, row: 0)), .blank)
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 1, row: 0)), .blank)
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 0, row: 1)), .blank)
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 1, row: 1)), .blank)
    }

    func testRowCellsReturnsRequestedRowInOrderWithoutExposingMutableStorage() {
        var grid = TerminalGrid(columns: 3, rows: 2)
        grid.setCell(TerminalCell(character: "A"), at: TerminalPoint(column: 0, row: 1))
        grid.setCell(TerminalCell(character: "B"), at: TerminalPoint(column: 1, row: 1))
        grid.setCell(TerminalCell(character: "C"), at: TerminalPoint(column: 2, row: 1))

        var row = grid.rowCells(1)

        XCTAssertEqual(row.map(\.character), ["A", "B", "C"])

        row[0] = .blank

        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 0, row: 1)).character, "A")
    }
}

extension TerminalCoreTests {
    func testParserEmitsPrintableText() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("abc".utf8))

        XCTAssertEqual(events, [.print("a"), .print("b"), .print("c")])
    }

    func testParserEmitsCursorMoveForCSIH() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}[3;5H".utf8))

        XCTAssertEqual(events, [.moveCursor(row: 2, column: 4)])
    }

    func testParserBoundsOversizedCSIParameters() {
        var parser = SwiftTerminalParser(maxParameterDigits: 4)

        let events = parser.parse(Array("\u{001B}[12345;1H".utf8))

        XCTAssertEqual(events, [.malformedSequence])
    }

    func testParserBoundsCSIParametersIndividually() {
        var parser = SwiftTerminalParser(maxParameterDigits: 4)

        let events = parser.parse(Array("\u{001B}[1234;1H".utf8))

        XCTAssertEqual(events, [.moveCursor(row: 1233, column: 0)])
    }
}
