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

    private func makeDefaults() -> UserDefaults {
        let suiteName = "wanda.geometry.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
