import Metal
import XCTest
@testable import Wanda

final class RenderingTests: XCTestCase {
    func testSnapshotCapturesGridCursorAndDirtyRows() {
        var model = TerminalModel(columns: 3, rows: 2, scrollbackLimit: 10)
        model.apply(.print("A"))

        let snapshot = TerminalRendererSnapshot(model: model)

        XCTAssertEqual(snapshot.columns, 3)
        XCTAssertEqual(snapshot.rows, 2)
        XCTAssertEqual(snapshot.cells.map(\.character), ["A", " ", " ", " ", " ", " "])
        XCTAssertEqual(snapshot.cursor, TerminalPoint(column: 1, row: 0))
        XCTAssertEqual(snapshot.dirtyRows, Set([0]))
    }

    func testGlyphAtlasComputesStableCellMetrics() throws {
        let atlas = try GlyphAtlas(fontName: "Menlo", fontSize: 14)

        XCTAssertGreaterThan(atlas.cellSize.width, 0)
        XCTAssertGreaterThan(atlas.cellSize.height, 0)

        let entry = try XCTUnwrap(atlas.glyph(for: "A"))
        XCTAssertEqual(entry.character, "A")
        XCTAssertGreaterThan(entry.advance, 0)
    }

    func testGlyphAtlasReportsMissingFont() {
        let fontName = "WandaMissingFontDefinitelyUnavailable"

        XCTAssertThrowsError(try GlyphAtlas(fontName: fontName, fontSize: 14)) { error in
            XCTAssertEqual(error as? GlyphAtlasError, .missingFont(fontName))
        }
    }

    func testGlyphAtlasDoesNotInventUnsupportedNonASCIIGlyphs() throws {
        let atlas = try GlyphAtlas(fontName: "Menlo", fontSize: 14)

        XCTAssertNil(atlas.glyph(for: "é"))
    }
}

extension RenderingTests {
    func testMetalRendererAcceptsSnapshot() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }

        let renderer = try TerminalMetalRenderer(device: device)
        var model = TerminalModel(columns: 2, rows: 1, scrollbackLimit: 5)
        model.apply(.print("A"))

        renderer.update(snapshot: TerminalRendererSnapshot(model: model))

        XCTAssertEqual(renderer.lastSnapshot?.cells.first?.character, "A")
    }
}
