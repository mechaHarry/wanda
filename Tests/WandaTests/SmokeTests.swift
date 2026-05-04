import XCTest
@testable import Wanda

final class SmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual("Wanda".count, 5)
    }
}
