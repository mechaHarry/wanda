import AppKit
import CoreGraphics
import XCTest
@testable import Wanda

final class GeometryStoreTests: XCTestCase {
    func testSavesAndLoadsWindowFrame() throws {
        let defaults = makeDefaults()
        let store = GeometryStore(defaults: defaults)
        let frame = CGRect(x: 10, y: 20, width: 800, height: 500)

        store.save(frame: frame)

        XCTAssertEqual(store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)), frame)
    }

    func testInvalidOffscreenFrameFallsBackToDefault() {
        let defaults = makeDefaults()
        let store = GeometryStore(defaults: defaults)

        store.save(frame: CGRect(x: 9000, y: 9000, width: 800, height: 500))

        XCTAssertEqual(
            store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            GeometryStore.defaultFrame
        )
    }

    func testMissingKeyFallsBackToDefault() {
        let store = GeometryStore(defaults: makeDefaults())

        XCTAssertEqual(
            store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            GeometryStore.defaultFrame
        )
    }

    func testEmptySavedStringFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("", forKey: "wanda.window.frame")
        let store = GeometryStore(defaults: defaults)

        XCTAssertEqual(
            store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            GeometryStore.defaultFrame
        )
    }

    func testMalformedSavedStringFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("not a rect", forKey: "wanda.window.frame")
        let store = GeometryStore(defaults: defaults)

        XCTAssertEqual(
            store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            GeometryStore.defaultFrame
        )
    }

    func testFrameNarrowerThanMinimumFallsBackToDefault() {
        let defaults = makeDefaults()
        let store = GeometryStore(defaults: defaults)

        store.save(frame: CGRect(x: 10, y: 20, width: 319, height: 500))

        XCTAssertEqual(
            store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            GeometryStore.defaultFrame
        )
    }

    func testFrameShorterThanMinimumFallsBackToDefault() {
        let defaults = makeDefaults()
        let store = GeometryStore(defaults: defaults)

        store.save(frame: CGRect(x: 10, y: 20, width: 800, height: 199))

        XCTAssertEqual(
            store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            GeometryStore.defaultFrame
        )
    }

    @MainActor
    func testWindowGeometryControllerRestoresFrameOnlyOncePerWindow() {
        let defaults = makeDefaults()
        let store = GeometryStore(defaults: defaults)
        let controller = TerminalWindowGeometryController(geometryStore: store)
        let windowToken = WindowToken()
        let savedFrame = CGRect(x: 20, y: 30, width: 820, height: 520)
        let currentFrame = CGRect(x: 100, y: 100, width: 720, height: 420)
        store.save(frame: savedFrame)

        let firstFrame = controller.frameToApply(
            to: ObjectIdentifier(windowToken),
            currentFrame: currentFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )
        let secondFrame = controller.frameToApply(
            to: ObjectIdentifier(windowToken),
            currentFrame: currentFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        XCTAssertEqual(firstFrame, savedFrame)
        XCTAssertNil(secondFrame)
    }

    @MainActor
    func testWindowGeometryControllerDoesNotApplyMatchingFrame() {
        let defaults = makeDefaults()
        let store = GeometryStore(defaults: defaults)
        let controller = TerminalWindowGeometryController(geometryStore: store)
        let windowToken = WindowToken()
        let savedFrame = CGRect(x: 20, y: 30, width: 820, height: 520)
        store.save(frame: savedFrame)

        let frame = controller.frameToApply(
            to: ObjectIdentifier(windowToken),
            currentFrame: savedFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        XCTAssertNil(frame)
    }

    @MainActor
    func testWindowGeometryControllerSavesFrame() {
        let defaults = makeDefaults()
        let store = GeometryStore(defaults: defaults)
        let controller = TerminalWindowGeometryController(geometryStore: store)
        let frame = CGRect(x: 50, y: 60, width: 880, height: 540)

        controller.save(frame: frame)

        XCTAssertEqual(
            store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            frame
        )
    }

    @MainActor
    func testWindowGeometryControllerObserveAppliesAndSavesObservedWindowFrame() {
        let defaults = makeDefaults()
        let store = GeometryStore(defaults: defaults)
        let controller = TerminalWindowGeometryController(geometryStore: store)
        let window = makeWindow(frame: CGRect(x: 25, y: 35, width: 720, height: 420))
        let savedFrame = GeometryStore.defaultFrame
        let movedFrame = CGRect(x: 140, y: 150, width: 840, height: 520)
        store.save(frame: savedFrame)

        controller.observe(window: window)
        XCTAssertEqual(window.frame, savedFrame)
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))

        window.setFrame(movedFrame, display: false)
        controller.saveCurrentWindowFrame()

        XCTAssertEqual(
            store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            movedFrame
        )
    }

    @MainActor
    func testWindowGeometryControllerRepeatedObserveDoesNotReapplyAfterUserResize() {
        let defaults = makeDefaults()
        let store = GeometryStore(defaults: defaults)
        let controller = TerminalWindowGeometryController(geometryStore: store)
        let window = makeWindow(frame: CGRect(x: 25, y: 35, width: 720, height: 420))
        let savedFrame = GeometryStore.defaultFrame
        let userFrame = CGRect(x: 180, y: 190, width: 860, height: 540)
        store.save(frame: savedFrame)

        controller.observe(window: window)
        XCTAssertEqual(window.frame, savedFrame)

        window.setFrame(userFrame, display: false)
        controller.observe(window: window)

        XCTAssertEqual(window.frame, userFrame)
    }

    @MainActor
    func testWindowGeometryControllerKeepsWeakObservedWindowReference() {
        let defaults = makeDefaults()
        let store = GeometryStore(defaults: defaults)
        let controller = TerminalWindowGeometryController(geometryStore: store)
        weak var weakWindow: NSWindow?

        autoreleasepool {
            let window = makeWindow(frame: CGRect(x: 25, y: 35, width: 720, height: 420))
            weakWindow = window

            controller.observe(window: window)
        }

        XCTAssertNil(weakWindow)
    }

    @MainActor
    func testWindowAccessViewDeliversOnlyOnWindowAttachmentChange() {
        let firstWindow = makeWindow(frame: CGRect(x: 25, y: 35, width: 720, height: 420))
        let secondWindow = makeWindow(frame: CGRect(x: 45, y: 55, width: 760, height: 460))
        var delivered: [(String, ObjectIdentifier)] = []
        let accessView = WindowAccessView { window in
            delivered.append(("initial", ObjectIdentifier(window)))
        }

        firstWindow.contentView?.addSubview(accessView)
        accessView.update { window in
            delivered.append(("updated", ObjectIdentifier(window)))
        }

        XCTAssertEqual(delivered.map(\.0), ["initial"])
        XCTAssertEqual(delivered.map(\.1), [ObjectIdentifier(firstWindow)])

        secondWindow.contentView?.addSubview(accessView)

        XCTAssertEqual(delivered.map(\.0), ["initial", "updated"])
        XCTAssertEqual(delivered.map(\.1), [ObjectIdentifier(firstWindow), ObjectIdentifier(secondWindow)])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "wanda.geometry.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    @MainActor
    private func makeWindow(frame: CGRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
        window.contentView = NSView(frame: CGRect(origin: .zero, size: frame.size))
        return window
    }
}

private final class WindowToken {}
