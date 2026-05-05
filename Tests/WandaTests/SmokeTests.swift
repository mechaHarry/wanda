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

    func testHandleKeyWithoutPTYDoesNotCreatePendingLatencyWork() async {
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: nil)

        viewModel.handleKey(.printable("a"))
        viewModel.framePresented(at: 1_000)
        await drainMainActorTasks()

        XCTAssertEqual(viewModel.debugActiveLatencyCount, 0)
        XCTAssertEqual(viewModel.debugPendingLatencyCount, 0)
        XCTAssertEqual(viewModel.debugCompletedLatencyCount, 0)
    }

    func testHandleKeyWritesToPTYAndCompletesPendingLatencyFIFO() async {
        let pty = FakePseudoTerminal()
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: pty)

        viewModel.handleKey(.printable("a"))
        viewModel.handleKey(.special(.returnKey, modifiers: []))
        viewModel.processOutput(Array("ab".utf8))

        XCTAssertEqual(pty.writes, [Array("a".utf8), [0x0D]])
        XCTAssertEqual(viewModel.debugPendingLatencyCount, 2)

        viewModel.framePresented(at: 1_000)
        await drainMainActorTasks()
        XCTAssertEqual(viewModel.debugPendingLatencyCount, 1)
        XCTAssertEqual(viewModel.debugCompletedLatencyCount, 1)

        viewModel.framePresented(at: 2_000)
        await drainMainActorTasks()

        XCTAssertEqual(viewModel.debugActiveLatencyCount, 0)
        XCTAssertEqual(viewModel.debugPendingLatencyCount, 0)
        XCTAssertEqual(viewModel.debugCompletedLatencyCount, 2)
        XCTAssertTrue(viewModel.debugCompletedLatencyMeasurements.allSatisfy { $0.modelMutated != nil })
    }

    func testHandleKeyWriteFailureDoesNotLeakPendingLatency() async {
        let pty = FakePseudoTerminal(writeError: .writeFailed(EBADF))
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: pty)

        viewModel.handleKey(.printable("x"))
        viewModel.framePresented(at: 1_000)
        await drainMainActorTasks()

        XCTAssertNotNil(viewModel.statusMessage)
        XCTAssertEqual(viewModel.debugActiveLatencyCount, 0)
        XCTAssertEqual(viewModel.debugPendingLatencyCount, 0)
        XCTAssertEqual(viewModel.debugCompletedLatencyCount, 0)
    }

    func testStopTerminatesPTYAndClearsPendingLatency() async {
        let pty = FakePseudoTerminal()
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: pty)

        viewModel.handleKey(.printable("a"))
        XCTAssertEqual(viewModel.debugPendingLatencyCount, 1)

        viewModel.stop()
        viewModel.framePresented(at: 1_000)
        await drainMainActorTasks()

        XCTAssertEqual(pty.terminateCallCount, 1)
        XCTAssertEqual(viewModel.debugActiveLatencyCount, 0)
        XCTAssertEqual(viewModel.debugPendingLatencyCount, 0)
        XCTAssertEqual(viewModel.debugCompletedLatencyCount, 0)
    }

    func testPendingLatencyIDsAreBounded() {
        let pty = FakePseudoTerminal()
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: pty)

        for _ in 0..<130 {
            viewModel.handleKey(.printable("a"))
        }

        XCTAssertEqual(pty.writes.count, 130)
        XCTAssertEqual(viewModel.debugActiveLatencyCount, 128)
        XCTAssertEqual(viewModel.debugPendingLatencyCount, 128)
    }

    private func drainMainActorTasks() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }
}

private final class FakePseudoTerminal: PseudoTerminal, @unchecked Sendable {
    var currentSize: TerminalSize
    var state: PseudoTerminalState = .running
    private(set) var writes: [[UInt8]] = []
    private(set) var terminateCallCount = 0
    private let writeError: PseudoTerminalError?

    init(
        size: TerminalSize = TerminalSize(columns: 80, rows: 24),
        writeError: PseudoTerminalError? = nil
    ) {
        self.currentSize = size
        self.writeError = writeError
    }

    func write(_ bytes: [UInt8]) throws {
        if let writeError {
            throw writeError
        }

        writes.append(bytes)
    }

    func resize(_ size: TerminalSize) throws {
        currentSize = size
    }

    func terminate() {
        terminateCallCount += 1
        state = .terminating
    }
}
