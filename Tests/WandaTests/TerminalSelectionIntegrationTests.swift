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

    func testPlainClickDoesNotCommitSelection() {
        let view = KeyCaptureView()
        var beganPoints: [TerminalPoint] = []
        var changedPoints: [TerminalPoint] = []
        view.layout = TerminalInputLayout(columns: 4, rows: 2, cellSize: CGSize(width: 10, height: 20))
        view.onSelectionBegan = { beganPoints.append($0) }
        view.onSelectionChanged = { changedPoints.append($0) }

        view.handleMouseDown(at: CGPoint(x: 5, y: 5), clickCount: 1)
        view.handleMouseUp(at: CGPoint(x: 5, y: 5))

        XCTAssertEqual(beganPoints, [])
        XCTAssertEqual(changedPoints, [])
    }

    func testKeyCaptureViewClaimsTransparentBoundsForMouseInput() {
        let view = KeyCaptureView(frame: CGRect(x: 0, y: 0, width: 100, height: 50))

        XCTAssertTrue(view.hitTest(CGPoint(x: 10, y: 10)) === view)
        XCTAssertNil(view.hitTest(CGPoint(x: 101, y: 10)))
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
        XCTAssertFalse(view.mouseDownCanMoveWindow)
    }

    func testDragCommitsSelectionAfterMovingToAnotherCell() {
        let view = KeyCaptureView()
        var beganPoints: [TerminalPoint] = []
        var changedPoints: [TerminalPoint] = []
        view.layout = TerminalInputLayout(columns: 4, rows: 2, cellSize: CGSize(width: 10, height: 20))
        view.onSelectionBegan = { beganPoints.append($0) }
        view.onSelectionChanged = { changedPoints.append($0) }

        view.handleMouseDown(at: CGPoint(x: 5, y: 5), clickCount: 1)
        view.handleMouseDragged(to: CGPoint(x: 25, y: 5))

        XCTAssertEqual(beganPoints, [TerminalPoint(column: 0, row: 0)])
        XCTAssertEqual(changedPoints, [TerminalPoint(column: 2, row: 0)])
    }

    func testInputLayoutFitsActualRenderedCellSize() {
        let layout = TerminalInputLayout(
            columns: 3,
            rows: 2,
            viewSize: CGSize(width: 100, height: 70)
        )

        XCTAssertEqual(layout.cellSize, CGSize(width: 100.0 / 3.0, height: 35))
        XCTAssertEqual(layout.point(for: CGPoint(x: 99, y: 69)), TerminalPoint(column: 2, row: 1))
    }

    func testTerminalSurfaceLayoutMapsInputToDisplayedSnapshotGrid() {
        let layout = TerminalSurfaceLayout(
            viewSize: CGSize(width: 900, height: 900),
            displayedColumns: 80,
            displayedRows: 30,
            preferredCellSize: CGSize(width: 9, height: 18)
        )

        XCTAssertEqual(layout.resizeColumns, 100)
        XCTAssertEqual(layout.resizeRows, 50)
        XCTAssertEqual(layout.inputLayout.columns, 80)
        XCTAssertEqual(layout.inputLayout.rows, 30)
        XCTAssertEqual(layout.inputLayout.point(for: CGPoint(x: 899, y: 899)), TerminalPoint(column: 79, row: 29))
    }

    func testSelectionOverlayRectsUseSnapshotGridAndIgnoreMouseHits() {
        let view = TerminalSelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 80, height: 40))
        let snapshot = TerminalRendererSnapshot(
            columns: 4,
            rows: 2,
            cells: Array(repeating: .blank, count: 8),
            cursor: TerminalPoint(column: 0, row: 0),
            dirtyRows: []
        )

        view.update(
            selection: TerminalSelection(
                start: TerminalPoint(column: 1, row: 0),
                end: TerminalPoint(column: 2, row: 1)
            ),
            snapshot: snapshot
        )

        XCTAssertEqual(
            view.selectionRects(in: CGSize(width: 80, height: 40)),
            [
                CGRect(x: 20, y: 0, width: 60, height: 20),
                CGRect(x: 0, y: 20, width: 60, height: 20)
            ]
        )
        XCTAssertNil(view.hitTest(CGPoint(x: 10, y: 10)))
        XCTAssertFalse(view.isOpaque)
    }

    func testRowRangesReturnEmptyWhenSelectionIsOutsideVisibleRows() {
        let selection = TerminalSelection(
            start: TerminalPoint(column: 0, row: 5),
            end: TerminalPoint(column: 2, row: 6)
        )

        XCTAssertEqual(selection.rowRanges(columns: 4, rows: 2), [])
    }

    func testRowRangesReturnEmptyWhenSelectionIsOutsideVisibleColumns() {
        let selection = TerminalSelection(
            start: TerminalPoint(column: 8, row: 0),
            end: TerminalPoint(column: 9, row: 0)
        )

        XCTAssertEqual(selection.rowRanges(columns: 4, rows: 2), [])
    }
}
