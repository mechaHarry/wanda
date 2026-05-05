import AppKit
import XCTest
@testable import Wanda

@MainActor
final class TerminalSelectionIntegrationTests: XCTestCase {
    func testViewModelTracksDragSelectionAndSelectedText() {
        let viewModel = TerminalViewModel(columns: 5, rows: 2, scrollbackLimit: 10)
        viewModel.processOutput(Array("helloworld".utf8))

        viewModel.beginSelection(at: TerminalPoint(column: 1, row: 0))
        viewModel.updateSelection(to: TerminalPoint(column: 2, row: 1))

        XCTAssertEqual(
            viewModel.selection,
            TerminalSelection(
                start: TerminalPoint(column: 1, row: 0),
                end: TerminalPoint(column: 2, row: 1)
            )
        )
        XCTAssertEqual(viewModel.selectedText(), "ello\nwor")
    }

    func testViewModelDoubleClickSelectsToken() {
        let viewModel = TerminalViewModel(columns: 9, rows: 1, scrollbackLimit: 10)
        viewModel.processOutput(Array("abc def".utf8))

        viewModel.selectToken(at: TerminalPoint(column: 1, row: 0))

        XCTAssertEqual(
            viewModel.selection,
            TerminalSelection(
                start: TerminalPoint(column: 0, row: 0),
                end: TerminalPoint(column: 2, row: 0)
            )
        )
        XCTAssertEqual(viewModel.selectedText(), "abc")
    }

    func testInputLayoutMapsTopLeftCoordinatesToClampedCells() {
        let layout = TerminalInputLayout(columns: 4, rows: 2, cellSize: CGSize(width: 10, height: 20))

        XCTAssertEqual(
            layout.point(for: CGPoint(x: 15, y: 25)),
            TerminalPoint(column: 1, row: 1)
        )
        XCTAssertEqual(
            layout.point(for: CGPoint(x: -3, y: -8)),
            TerminalPoint(column: 0, row: 0)
        )
        XCTAssertEqual(
            layout.point(for: CGPoint(x: 99, y: 99)),
            TerminalPoint(column: 3, row: 1)
        )
    }

    func testClipboardWriterCopiesSelectedText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WandaSelectionIntegrationTests"))

        XCTAssertTrue(TerminalSelectionClipboard.copy("selected text", to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "selected text")
    }
}
