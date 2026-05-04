import CoreGraphics
import XCTest
@testable import Wanda

final class GeometryStoreTests: XCTestCase {
    func testSavesAndLoadsWindowFrame() throws {
        let defaults = UserDefaults(suiteName: "wanda.geometry.test.\(UUID().uuidString)")!
        let store = GeometryStore(defaults: defaults)
        let frame = CGRect(x: 10, y: 20, width: 800, height: 500)

        store.save(frame: frame)

        XCTAssertEqual(store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)), frame)
    }

    func testInvalidOffscreenFrameFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "wanda.geometry.test.\(UUID().uuidString)")!
        let store = GeometryStore(defaults: defaults)

        store.save(frame: CGRect(x: 9000, y: 9000, width: 800, height: 500))

        XCTAssertEqual(
            store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            GeometryStore.defaultFrame
        )
    }
}
