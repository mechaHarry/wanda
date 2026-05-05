import XCTest
@testable import Wanda

@MainActor
final class SmokeTests: XCTestCase {
    func testViewModelAppliesOutputBytesToSnapshot() {
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10)

        viewModel.processOutput(Array("ok".utf8))

        XCTAssertEqual(viewModel.snapshot?.cells[0].character, "o")
        XCTAssertEqual(viewModel.snapshot?.cells[1].character, "k")
    }
}
