import Foundation
import Metal
import MetalKit
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

    func testGlyphAtlasBuildsTextureCoordinates() throws {
        let atlas = try GlyphAtlas(fontName: "Menlo", fontSize: 14)

        XCTAssertGreaterThan(atlas.atlasSize.width, atlas.cellSize.width)
        XCTAssertGreaterThan(atlas.atlasSize.height, atlas.cellSize.height)
        XCTAssertGreaterThan(atlas.image.width, 0)
        XCTAssertGreaterThan(atlas.image.height, 0)

        let entry = try XCTUnwrap(atlas.glyph(for: "A"))
        XCTAssertGreaterThan(entry.textureRect.width, 0)
        XCTAssertGreaterThan(entry.textureRect.height, 0)
        XCTAssertGreaterThanOrEqual(entry.textureRect.minX, 0)
        XCTAssertGreaterThanOrEqual(entry.textureRect.minY, 0)
        XCTAssertLessThanOrEqual(entry.textureRect.maxX, atlas.atlasSize.width)
        XCTAssertLessThanOrEqual(entry.textureRect.maxY, atlas.atlasSize.height)
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

    func testRendererBuildsVerticesForVisibleCells() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }

        let renderer = try TerminalMetalRenderer(device: device)
        var model = TerminalModel(columns: 2, rows: 1, scrollbackLimit: 5)
        model.apply(.print("A"))

        renderer.update(snapshot: TerminalRendererSnapshot(model: model))

        XCTAssertEqual(renderer.debugVertexCount, 6)
    }

    func testRendererSkipsBlankSpacesWhenBuildingVertices() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }

        let renderer = try TerminalMetalRenderer(device: device)
        let model = TerminalModel(columns: 2, rows: 1, scrollbackLimit: 5)

        renderer.update(snapshot: TerminalRendererSnapshot(model: model))

        XCTAssertEqual(renderer.debugVertexCount, 0)
    }

    @MainActor
    func testTerminalMetalViewUsesOnDemandConfiguration() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable")
        }

        let view = try TerminalMetalView()

        XCTAssertEqual(view.colorPixelFormat, .bgra8Unorm)
        XCTAssertTrue(view.framebufferOnly)
        XCTAssertTrue(view.enableSetNeedsDisplay)
        XCTAssertTrue(view.isPaused)
        XCTAssertTrue(view.delegate === view.terminalRenderer)
        XCTAssertTrue(view.device === view.terminalRenderer.device)
    }

    func testMetalRendererFrameCallbackRunsOnMainActor() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }

        let expectation = expectation(description: "frame callback")
        let probe = FrameCallbackProbe()
        let renderer = try TerminalMetalRenderer(device: device) { _ in
            probe.recordCallbackThread()
            expectation.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            renderer.notifyFramePresentedForTesting(timestamp: 1)
        }
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertTrue(probe.wasCallbackOnMainThread)
    }
}

private final class FrameCallbackProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callbackWasOnMainThread = false

    var wasCallbackOnMainThread: Bool {
        lock.withLock {
            callbackWasOnMainThread
        }
    }

    func recordCallbackThread() {
        lock.withLock {
            callbackWasOnMainThread = Thread.isMainThread
        }
    }
}
