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

    func testReplaceRowUpdatesOnlyRequestedRow() {
        var grid = TerminalGrid(columns: 3, rows: 2)
        grid.setCell(TerminalCell(character: "A"), at: TerminalPoint(column: 0, row: 0))

        grid.replaceRow(1, with: [
            TerminalCell(character: "X"),
            TerminalCell(character: "Y"),
            TerminalCell(character: "Z"),
        ])

        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 0, row: 0)).character, "A")
        XCTAssertEqual(grid.rowCells(1).map(\.character), ["X", "Y", "Z"])
    }

    func testScrollUpOneLineReturnsRemovedRowAndBlanksLastRow() {
        var grid = TerminalGrid(columns: 2, rows: 3)
        for (point, character) in [
            (TerminalPoint(column: 0, row: 0), Character("A")),
            (TerminalPoint(column: 1, row: 0), Character("B")),
            (TerminalPoint(column: 0, row: 1), Character("C")),
            (TerminalPoint(column: 1, row: 1), Character("D")),
            (TerminalPoint(column: 0, row: 2), Character("E")),
            (TerminalPoint(column: 1, row: 2), Character("F")),
        ] {
            grid.setCell(TerminalCell(character: character), at: point)
        }

        let removed = grid.scrollUpOneLine()

        XCTAssertEqual(removed.map(\.character), ["A", "B"])
        XCTAssertEqual(grid.rowCells(0).map(\.character), ["C", "D"])
        XCTAssertEqual(grid.rowCells(1).map(\.character), ["E", "F"])
        XCTAssertEqual(grid.rowCells(2), [.blank, .blank])
    }

    func testGridResizePreservesOverlappingTopLeftContentAndFillsBlanks() {
        var grid = TerminalGrid(columns: 3, rows: 2)
        grid.setCell(TerminalCell(character: "A"), at: TerminalPoint(column: 0, row: 0))
        grid.setCell(TerminalCell(character: "B"), at: TerminalPoint(column: 2, row: 0))
        grid.setCell(TerminalCell(character: "C"), at: TerminalPoint(column: 1, row: 1))

        grid.resize(columns: 4, rows: 3)

        XCTAssertEqual(grid.columns, 4)
        XCTAssertEqual(grid.rows, 3)
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 0, row: 0)).character, "A")
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 2, row: 0)).character, "B")
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 1, row: 1)).character, "C")
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 3, row: 0)), .blank)
        XCTAssertEqual(grid.rowCells(2), [.blank, .blank, .blank, .blank])

        grid.resize(columns: 2, rows: 1)

        XCTAssertEqual(grid.columns, 2)
        XCTAssertEqual(grid.rows, 1)
        XCTAssertEqual(grid.rowCells(0).map(\.character), ["A", " "])
    }

    func testModelResizeShrinksFromTopAndPreservesBottomContent() {
        var model = TerminalModel(columns: 4, rows: 4, scrollbackLimit: 10)
        writeRows(["1111", "2222", "3333", "4444"], into: &model)
        model.apply(.moveCursor(row: 3, column: 2))

        model.resize(columns: 4, rows: 2)

        XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)), "3333")
        XCTAssertEqual(String(model.visibleGrid.rowCells(1).map(\.character)), "4444")
        XCTAssertEqual(model.cursor, TerminalPoint(column: 2, row: 1))
        XCTAssertEqual(model.scrollback.suffix(2).map { String($0.map(\.character)) }, ["1111", "2222"])
    }

    func testModelResizeGrowsFromScrollbackWithoutLosingVisibleContent() {
        var model = TerminalModel(columns: 4, rows: 4, scrollbackLimit: 10)
        writeRows(["1111", "2222", "3333", "4444"], into: &model)
        model.apply(.moveCursor(row: 3, column: 2))

        model.resize(columns: 4, rows: 2)
        model.resize(columns: 4, rows: 4)

        XCTAssertEqual((0..<4).map { String(model.visibleGrid.rowCells($0).map(\.character)) }, [
            "1111",
            "2222",
            "3333",
            "4444",
        ])
        XCTAssertEqual(model.cursor, TerminalPoint(column: 2, row: 3))
    }
}

private func writeRows(_ rows: [String], into model: inout TerminalModel) {
    for (row, text) in rows.enumerated() {
        model.apply(.moveCursor(row: row, column: 0))
        for character in text {
            model.apply(.print(character))
        }
    }
}

extension TerminalCoreTests {
    func testParserEmitsPrintableText() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("abc".utf8))

        XCTAssertEqual(events, [.print("a"), .print("b"), .print("c")])
    }

    func testParserEmitsUTF8PrintableText() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("❯éΩ".utf8))

        XCTAssertEqual(events, [.print("❯"), .print("é"), .print("Ω")])
    }

    func testParserCarriesSplitUTF8StateAcrossParseCalls() {
        var parser = SwiftTerminalParser()
        let bytes = Array("❯".utf8)

        let firstEvents = parser.parse(Array(bytes.prefix(2)))
        let secondEvents = parser.parse(Array(bytes.suffix(1)))

        XCTAssertEqual(firstEvents, [])
        XCTAssertEqual(secondEvents, [.print("❯")])
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

    func testParserPreservesEmptyCursorParameterDefaults() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}[;5H".utf8))

        XCTAssertEqual(events, [.moveCursor(row: 0, column: 4)])
    }

    func testParserBoundsCSISeparatorGrowth() {
        var parser = SwiftTerminalParser(maxParameterDigits: 4, maxCSIBufferLength: 4)

        let events = parser.parse(Array("\u{001B}[;;;;;H".utf8))

        XCTAssertEqual(events, [.malformedSequence])
    }

    func testParserCarriesSplitCSIStateAcrossParseCalls() {
        var parser = SwiftTerminalParser()

        let firstEvents = parser.parse(Array("\u{001B}[3".utf8))
        let secondEvents = parser.parse(Array(";5H".utf8))

        XCTAssertEqual(firstEvents, [])
        XCTAssertEqual(secondEvents, [.moveCursor(row: 2, column: 4)])
    }

    func testParserEmitsControlEvents() {
        var parser = SwiftTerminalParser()

        let events = parser.parse([0x08, 0x0A, 0x0D])

        XCTAssertEqual(events, [.backspace, .lineFeed, .carriageReturn])
    }

    func testParserEmitsClearAndSGREvents() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}[2J\u{001B}[K\u{001B}[m\u{001B}[31;1m".utf8))

        XCTAssertEqual(events, [
            .eraseScreen(.all),
            .eraseLine(.cursorToEnd),
            .setGraphicRendition([0]),
            .setGraphicRendition([31, 1])
        ])
    }

    func testParserEmitsCursorHorizontalAbsolute() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}[3G".utf8))

        XCTAssertEqual(events, [.cursorHorizontalAbsolute(column: 2)])
    }

    func testParserEmitsEraseScreenModes() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}[J\u{001B}[0J\u{001B}[1J\u{001B}[2J".utf8))

        XCTAssertEqual(events, [
            .eraseScreen(.cursorToEnd),
            .eraseScreen(.cursorToEnd),
            .eraseScreen(.startToCursor),
            .eraseScreen(.all),
        ])
    }

    func testParserEmitsEraseLineModes() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}[K\u{001B}[0K\u{001B}[1K\u{001B}[2K".utf8))

        XCTAssertEqual(events, [
            .eraseLine(.cursorToEnd),
            .eraseLine(.cursorToEnd),
            .eraseLine(.startToCursor),
            .eraseLine(.all),
        ])
    }

    func testParserEmitsAlternateScreenEvents() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}[?1049h\u{001B}[?1049l".utf8))

        XCTAssertEqual(events, [.useAlternateScreen(true), .useAlternateScreen(false)])
    }

    func testParserDiscardsOSCTitleSequenceWithoutPrintingPayload() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}]0;/\u{0007}A".utf8))

        XCTAssertEqual(events, [.print("A")])
    }

    func testModelKeepsUTF8PromptGlyphThroughZshPromptRedraw() {
        var parser = SwiftTerminalParser()
        var model = TerminalModel(columns: 80, rows: 8, scrollbackLimit: 10)
        let output = [
            "\u{001B}]0;/\u{0007}\r\n",
            "\u{001B}[0m\u{001B}[27m\u{001B}[24m\u{001B}[J\u{001B}[34m/\u{001B}[39m\r\n",
            "\r\u{001B}[35m❯\u{001B}[39m \u{001B}[K\u{001B}[?2004h",
            "\r\r\u{001B}[A\u{001B}[0m\u{001B}[27m\u{001B}[24m\u{001B}[J\u{001B}[34m/\u{001B}[39m\r\n",
            "\r\u{001B}[35m❯\u{001B}[39m \u{001B}[K",
        ].joined()
        let bytes = Array(output.utf8)

        for event in parser.parse(bytes) {
            model.apply(event)
        }

        let snapshot = TerminalRendererSnapshot(model: model)
        let visibleText = (0..<snapshot.rows).map { row in
            let start = row * snapshot.columns
            let end = min(start + snapshot.columns, snapshot.cells.count)
            return snapshot.cells[start..<end].map(\.character).map(String.init).joined()
        }.joined(separator: "\n")

        XCTAssertTrue(visibleText.contains("❯"))
    }

    func testModelKeepsUTF8PromptGlyphAfterCommandAndPromptReturn() {
        var parser = SwiftTerminalParser()
        var model = TerminalModel(columns: 80, rows: 8, scrollbackLimit: 10)
        let output = [
            "\u{001B}[34m/\u{001B}[39m\r\n",
            "\r\u{001B}[35m❯\u{001B}[39m \u{001B}[K\u{001B}[?2004h",
            "p\u{0008}pwd\u{0008}\u{0008}\u{0008}\u{001B}[32mp\u{001B}[32mw\u{001B}[32md\u{001B}[39m\u{001B}[?2004l\r\r\n",
            "\u{001B}]0;wanda: pwd\u{0007}/\r\n",
            "\u{001B}]0;/\u{0007}\r\n",
            "\u{001B}[0m\u{001B}[27m\u{001B}[24m\u{001B}[J\u{001B}[34m/\u{001B}[39m\r\n",
            "\r\u{001B}[35m❯\u{001B}[39m \u{001B}[K\u{001B}[?2004h",
        ].joined()
        let bytes = Array(output.utf8)

        for event in parser.parse(bytes) {
            model.apply(event)
        }

        let snapshot = TerminalRendererSnapshot(model: model)
        let promptCount = snapshot.cells.filter { $0.character == "❯" }.count

        XCTAssertGreaterThanOrEqual(promptCount, 1)
    }

    func testParserCarriesSplitOSCStateAcrossParseCalls() {
        var parser = SwiftTerminalParser()

        let firstEvents = parser.parse(Array("\u{001B}]0;/".utf8))
        let secondEvents = parser.parse(Array("\u{0007}A".utf8))

        XCTAssertEqual(firstEvents, [])
        XCTAssertEqual(secondEvents, [.print("A")])
    }

    func testParserDiscardsOSCWithStringTerminator() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}]2;Wanda\u{001B}\\A".utf8))

        XCTAssertEqual(events, [.print("A")])
    }

    func testParserRecoversAfterMalformedEscape() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}XA".utf8))

        XCTAssertEqual(events, [.malformedSequence, .print("A")])
    }
}

extension TerminalCoreTests {
    func testModelPrintsAndAdvancesCursor() {
        var model = TerminalModel(columns: 4, rows: 2, scrollbackLimit: 10)

        model.apply(.print("A"))
        model.apply(.print("B"))

        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, "A")
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 1, row: 0)).character, "B")
        XCTAssertEqual(model.cursor, TerminalPoint(column: 2, row: 0))
        XCTAssertEqual(model.dirtyRows, Set([0]))
    }

    func testModelScrollsIntoBoundedScrollback() {
        var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 1)

        for character in "abcdefgh" {
            model.apply(.print(character))
        }

        XCTAssertEqual(model.scrollback.count, 1)
        XCTAssertEqual(String(model.scrollback[0].map(\.character)), "cd")
        XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)), "ef")
    }

    func testAlternateScreenDoesNotMutateScrollback() {
        var model = TerminalModel(columns: 3, rows: 2, scrollbackLimit: 5)
        model.apply(.print("A"))

        model.apply(.useAlternateScreen(true))
        model.apply(.print("B"))
        model.apply(.useAlternateScreen(false))

        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, "A")
        XCTAssertEqual(model.scrollback.count, 0)
    }

    func testModelAppliesCursorControlsAndClearsDirtyRows() {
        var model = TerminalModel(columns: 4, rows: 2, scrollbackLimit: 5)
        model.apply(.moveCursor(row: 0, column: 2))
        model.apply(.print("X"))
        model.apply(.backspace)
        model.apply(.print("Y"))
        model.apply(.carriageReturn)
        model.apply(.lineFeed)

        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 2, row: 0)).character, "Y")
        XCTAssertEqual(model.cursor, TerminalPoint(column: 0, row: 1))
        XCTAssertEqual(model.drainDirtyRows(), Set([0, 1]))
        XCTAssertEqual(model.dirtyRows, [])
    }

    func testModelAppliesClearEventsAndSGRAttributes() {
        var model = TerminalModel(columns: 3, rows: 2, scrollbackLimit: 5)

        model.apply(.setGraphicRendition([1, 3, 4, 7, 31, 44]))
        model.apply(.print("A"))

        let styledCell = model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0))
        XCTAssertEqual(styledCell.attributes.foreground, .ansi(index: 1))
        XCTAssertEqual(styledCell.attributes.background, .ansi(index: 4))
        XCTAssertTrue(styledCell.attributes.isBold)
        XCTAssertTrue(styledCell.attributes.isItalic)
        XCTAssertTrue(styledCell.attributes.isUnderline)
        XCTAssertTrue(styledCell.attributes.isInverse)

        model.apply(.eraseLine(.all))
        XCTAssertEqual(model.visibleGrid.rowCells(0), [.blank, .blank, .blank])

        model.apply(.setGraphicRendition([0]))
        model.apply(.print("B"))
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 1, row: 0)).attributes, TerminalAttributes())

        model.apply(.eraseScreen(.all))
        XCTAssertEqual(model.visibleGrid.rowCells(0), [.blank, .blank, .blank])
        XCTAssertEqual(model.visibleGrid.rowCells(1), [.blank, .blank, .blank])
    }

    func testModelEraseLineModesClearOnlyRequestedLineRange() {
        var model = TerminalModel(columns: 5, rows: 1, scrollbackLimit: 5)
        for character in "abcde" {
            model.apply(.print(character))
        }

        model.apply(.moveCursor(row: 0, column: 2))
        model.apply(.eraseLine(.cursorToEnd))
        XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)), "ab   ")

        for character in "cde" {
            model.apply(.print(character))
        }
        model.apply(.moveCursor(row: 0, column: 2))
        model.apply(.eraseLine(.startToCursor))
        XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)), "   de")
    }

    func testModelClearsUnderlineWithSGR24() {
        var model = TerminalModel(columns: 3, rows: 1, scrollbackLimit: 5)

        model.apply(.setGraphicRendition([4]))
        model.apply(.print("A"))
        model.apply(.setGraphicRendition([24]))
        model.apply(.print("B"))

        XCTAssertTrue(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).attributes.isUnderline)
        XCTAssertFalse(model.visibleGrid.cell(at: TerminalPoint(column: 1, row: 0)).attributes.isUnderline)
    }

    func testModelCursorHorizontalAbsoluteKeepsCurrentRow() {
        var model = TerminalModel(columns: 6, rows: 2, scrollbackLimit: 5)
        for character in "abc" {
            model.apply(.print(character))
        }
        model.apply(.carriageReturn)
        model.apply(.lineFeed)
        for character in "def" {
            model.apply(.print(character))
        }

        model.apply(.cursorHorizontalAbsolute(column: 1))
        model.apply(.print("/"))

        XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)), "abc   ")
        XCTAssertEqual(String(model.visibleGrid.rowCells(1).map(\.character)), "d/f   ")
        XCTAssertEqual(model.cursor, TerminalPoint(column: 2, row: 1))
    }

    func testModelEraseFromCursorToEndPreservesEarlierOutput() {
        var model = TerminalModel(columns: 4, rows: 3, scrollbackLimit: 5)
        for character in "abcdefgh" {
            model.apply(.print(character))
        }

        model.apply(.moveCursor(row: 1, column: 1))
        model.apply(.eraseScreen(.cursorToEnd))

        XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)), "abcd")
        XCTAssertEqual(String(model.visibleGrid.rowCells(1).map(\.character)), "e   ")
        XCTAssertEqual(String(model.visibleGrid.rowCells(2).map(\.character)), "    ")
    }

    func testModelEraseStartToCursorPreservesLaterOutput() {
        var model = TerminalModel(columns: 4, rows: 3, scrollbackLimit: 5)
        for character in "abcdefghijkl" {
            model.apply(.print(character))
        }

        model.apply(.moveCursor(row: 1, column: 2))
        model.apply(.eraseScreen(.startToCursor))

        XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)), "    ")
        XCTAssertEqual(String(model.visibleGrid.rowCells(1).map(\.character)), "   h")
        XCTAssertEqual(String(model.visibleGrid.rowCells(2).map(\.character)), "ijkl")
    }

    func testModelEraseAllClearsVisibleScreenWithoutMovingCursorOrScrollback() {
        var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 5)
        for character in "abcdef" {
            model.apply(.print(character))
        }
        let scrollbackCount = model.scrollback.count

        model.apply(.moveCursor(row: 1, column: 1))
        model.apply(.eraseScreen(.all))

        XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 1))
        XCTAssertEqual(model.visibleGrid.rowCells(0), [.blank, .blank])
        XCTAssertEqual(model.visibleGrid.rowCells(1), [.blank, .blank])
        XCTAssertEqual(model.scrollback.count, scrollbackCount)
    }

    func testModelShellLikePromptRedrawDoesNotClearPreviousCommandOutput() {
        var model = TerminalModel(columns: 12, rows: 4, scrollbackLimit: 5)
        for character in "echo hi" {
            model.apply(.print(character))
        }
        model.apply(.carriageReturn)
        model.apply(.lineFeed)
        for character in "hi" {
            model.apply(.print(character))
        }
        model.apply(.carriageReturn)
        model.apply(.lineFeed)

        model.apply(.eraseScreen(.cursorToEnd))
        for character in "$ " {
            model.apply(.print(character))
        }

        XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)).prefix(7), "echo hi")
        XCTAssertEqual(String(model.visibleGrid.rowCells(1).map(\.character)).prefix(2), "hi")
        XCTAssertEqual(String(model.visibleGrid.rowCells(2).map(\.character)).prefix(2), "$ ")
    }

    func testModelEraseAllClearsScreenAndPendingWrapWithoutMovingCursor() {
        var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 5)
        model.apply(.print("A"))
        model.apply(.print("B"))

        model.apply(.eraseScreen(.all))

        XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 0))

        model.apply(.print("C"))

        XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 0))
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, " ")
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 1, row: 0)).character, "C")
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 1)).character, " ")
    }

    func testModelEraseFromCursorToEndClearsPendingWrapWithoutMovingCursor() {
        var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 5)
        model.apply(.print("A"))
        model.apply(.print("B"))

        model.apply(.eraseScreen(.cursorToEnd))

        XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 0))

        model.apply(.print("C"))

        XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 0))
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, "A")
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 1, row: 0)).character, "C")
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 1)).character, " ")
    }

    func testModelEraseStartToCursorClearsPendingWrapWithoutMovingCursor() {
        var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 5)
        model.apply(.print("A"))
        model.apply(.print("B"))

        model.apply(.eraseScreen(.startToCursor))

        XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 0))

        model.apply(.print("C"))

        XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 0))
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, " ")
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 1, row: 0)).character, "C")
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 1)).character, " ")
    }

    func testModelCursorMovementMarksOldAndNewRowsDirty() {
        var model = TerminalModel(columns: 4, rows: 2, scrollbackLimit: 5)
        _ = model.drainDirtyRows()

        model.apply(.moveCursor(row: 1, column: 0))

        XCTAssertEqual(model.dirtyRows, Set([0, 1]))
    }

    func testModelSameRowCursorMovementMarksRowDirty() {
        var model = TerminalModel(columns: 4, rows: 2, scrollbackLimit: 5)
        _ = model.drainDirtyRows()

        model.apply(.moveCursor(row: 0, column: 2))

        XCTAssertEqual(model.dirtyRows, Set([0]))
    }

    func testModelMalformedSequenceIsNoOp() {
        var model = TerminalModel(columns: 4, rows: 2, scrollbackLimit: 5)
        model.apply(.print("A"))
        _ = model.drainDirtyRows()
        let before = model

        model.apply(.malformedSequence)

        XCTAssertEqual(model, before)
    }

    func testModelZeroScrollbackLimitRetainsNoScrollback() {
        var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 0)

        for character in "abcdefgh" {
            model.apply(.print(character))
        }

        XCTAssertEqual(model.scrollback.count, 0)
    }

    func testModelAlternateScreenScrollingDoesNotMutateScrollback() {
        var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 5)

        model.apply(.useAlternateScreen(true))
        for character in "abcdefgh" {
            model.apply(.print(character))
        }
        model.apply(.useAlternateScreen(false))

        XCTAssertEqual(model.scrollback.count, 0)
    }

    func testModelAlternateScreenHasIndependentGridAndCursor() {
        var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 5)
        model.apply(.print("A"))

        model.apply(.useAlternateScreen(true))
        XCTAssertTrue(model.isUsingAlternateScreen)
        XCTAssertEqual(model.cursor, TerminalPoint(column: 0, row: 0))

        model.apply(.print("B"))
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, "B")

        model.apply(.useAlternateScreen(false))
        XCTAssertFalse(model.isUsingAlternateScreen)
        XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 0))
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, "A")
    }

    func testModelResizePreservesContentClampsCursorAndMarksVisibleRowsDirty() {
        var model = TerminalModel(columns: 4, rows: 2, scrollbackLimit: 5)
        model.apply(.print("A"))
        model.apply(.moveCursor(row: 1, column: 1))
        model.apply(.print("B"))
        model.apply(.moveCursor(row: 1, column: 3))

        model.resize(columns: 2, rows: 1)

        XCTAssertEqual(model.visibleGrid.columns, 2)
        XCTAssertEqual(model.visibleGrid.rows, 1)
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 1, row: 0)).character, "B")
        XCTAssertEqual(model.scrollback.last?.map(\.character), ["A", " ", " ", " "])
        XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 0))
        XCTAssertEqual(model.dirtyRows, Set([0]))

        model.apply(.print("C"))

        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 1, row: 0)).character, "C")
    }

    func testModelResizeKeepsPrimaryAndAlternateScreenDimensionsAligned() {
        var model = TerminalModel(columns: 3, rows: 2, scrollbackLimit: 5)
        model.apply(.print("P"))
        model.apply(.useAlternateScreen(true))
        model.apply(.print("A"))

        model.resize(columns: 4, rows: 3)

        XCTAssertEqual(model.visibleGrid.columns, 4)
        XCTAssertEqual(model.visibleGrid.rows, 3)
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, "A")

        model.apply(.useAlternateScreen(false))

        XCTAssertEqual(model.visibleGrid.columns, 4)
        XCTAssertEqual(model.visibleGrid.rows, 3)
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, "P")
    }
}
