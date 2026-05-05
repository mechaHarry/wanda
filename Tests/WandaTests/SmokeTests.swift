import Foundation
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

    func testResizeIgnoresInvalidSizesAndPropagatesValidSize() {
        let pty = FakePseudoTerminal()
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: pty)

        viewModel.resize(columns: 0, rows: 24)
        viewModel.resize(columns: 80, rows: 0)
        viewModel.resize(columns: -1, rows: 24)
        viewModel.resize(columns: 100, rows: 40)

        XCTAssertEqual(pty.resizes, [TerminalSize(columns: 100, rows: 40)])
        XCTAssertEqual(pty.currentSize, TerminalSize(columns: 100, rows: 40))
        XCTAssertEqual(viewModel.snapshot?.columns, 100)
        XCTAssertEqual(viewModel.snapshot?.rows, 40)
        XCTAssertNil(viewModel.statusMessage)
    }

    func testResizeWithoutPTYUpdatesSnapshotDimensions() {
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: nil)
        viewModel.processOutput(Array("ab".utf8))

        viewModel.resize(columns: 6, rows: 3)

        XCTAssertEqual(viewModel.snapshot?.columns, 6)
        XCTAssertEqual(viewModel.snapshot?.rows, 3)
        XCTAssertEqual(viewModel.snapshot?.cells[0].character, "a")
        XCTAssertEqual(viewModel.snapshot?.cells[1].character, "b")
        XCTAssertNil(viewModel.statusMessage)
    }

    func testResizeFailureSetsStatusMessage() {
        let pty = FakePseudoTerminal(resizeError: .resizeFailed(EBADF))
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: pty)
        let initialColumns = viewModel.snapshot?.columns
        let initialRows = viewModel.snapshot?.rows

        viewModel.resize(columns: 100, rows: 40)

        XCTAssertEqual(pty.resizes, [])
        XCTAssertEqual(viewModel.snapshot?.columns, initialColumns)
        XCTAssertEqual(viewModel.snapshot?.rows, initialRows)
        XCTAssertTrue(viewModel.statusMessage?.contains("Failed to resize terminal") == true)
    }

    func testStartDefaultShellStartsOutputPumpForInjectedPTYAndAppliesReadBytes() async {
        let pty = FakePseudoTerminal(readResults: [.bytes(Array("z".utf8))])
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: pty)

        viewModel.startDefaultShell()

        let rendered = await waitForCondition {
            viewModel.snapshot?.cells[0].character == "z"
        }

        XCTAssertTrue(rendered)
        XCTAssertGreaterThan(pty.readCallCount, 0)
        viewModel.stop()
    }

    func testOutputPumpDrainsQueuedChunksBeforeSleeping() async {
        let pty = FakePseudoTerminal(readResults: [
            .bytes(Array("a".utf8)),
            .bytes(Array("b".utf8)),
            .bytes(Array("c".utf8)),
            .empty,
        ])
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: pty)

        viewModel.startDefaultShell()

        let rendered = await waitForCondition {
            viewModel.snapshot?.cells.prefix(3).map(\.character) == ["a", "b", "c"]
        }

        XCTAssertTrue(rendered)
        XCTAssertEqual(pty.readCallCount, 4)
        XCTAssertEqual(viewModel.debugOutputPumpBatchCount, 1)
        viewModel.stop()
    }

    func testOutputPumpBoundsLargeBurstIntoMultipleBatches() async {
        let chunk = [UInt8](repeating: Character("x").asciiValue!, count: 4_096)
        let chunkCount = 20
        let totalByteCount = chunk.count * chunkCount
        let pty = FakePseudoTerminal(
            readResults: Array(repeating: .bytes(chunk), count: chunkCount) + [.empty]
        )
        let viewModel = TerminalViewModel(
            columns: totalByteCount + 1,
            rows: 1,
            scrollbackLimit: 10,
            pty: pty
        )

        viewModel.startDefaultShell()

        let rendered = await waitForCondition {
            viewModel.snapshot?.cells[totalByteCount - 1].character == "x"
        }

        XCTAssertTrue(rendered)
        XCTAssertEqual(pty.readCallCount, chunkCount + 1)
        XCTAssertGreaterThan(viewModel.debugOutputPumpBatchCount, 1)
        viewModel.stop()
    }

    func testOutputPumpReadFailureSetsStatusMessage() async {
        let pty = FakePseudoTerminal(readResults: [.failure(.readFailed(EBADF))])
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: pty)

        viewModel.startDefaultShell()

        let surfacedError = await waitForCondition {
            viewModel.statusMessage?.contains("Failed to read from terminal") == true
        }

        XCTAssertTrue(surfacedError)
        XCTAssertFalse(viewModel.debugHasOutputTask)
        viewModel.stop()
    }

    func testStopTerminatesPTYAndClearsPendingLatency() async {
        let pty = FakePseudoTerminal()
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10, pty: pty)

        viewModel.startDefaultShell()
        XCTAssertTrue(viewModel.debugHasOutputTask)

        viewModel.handleKey(.printable("a"))
        XCTAssertEqual(viewModel.debugPendingLatencyCount, 1)

        viewModel.stop()
        viewModel.framePresented(at: 1_000)
        await drainMainActorTasks()

        XCTAssertEqual(pty.terminateCallCount, 1)
        XCTAssertFalse(viewModel.debugHasOutputTask)
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

    private func waitForCondition(
        timeoutNanoseconds: UInt64 = 500_000_000,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return true
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        return condition()
    }
}

private enum FakeReadResult {
    case bytes([UInt8])
    case empty
    case failure(PseudoTerminalError)
}

private final class FakePseudoTerminal: PseudoTerminal, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSize: TerminalSize
    private var storedState: PseudoTerminalState = .running
    private var storedWrites: [[UInt8]] = []
    private var storedResizes: [TerminalSize] = []
    private var storedTerminateCallCount = 0
    private var storedReadCallCount = 0
    private var readResults: [FakeReadResult]
    private let writeError: PseudoTerminalError?
    private let resizeError: PseudoTerminalError?

    var currentSize: TerminalSize {
        lock.withLock { storedSize }
    }

    var state: PseudoTerminalState {
        lock.withLock { storedState }
    }

    var writes: [[UInt8]] {
        lock.withLock { storedWrites }
    }

    var resizes: [TerminalSize] {
        lock.withLock { storedResizes }
    }

    var terminateCallCount: Int {
        lock.withLock { storedTerminateCallCount }
    }

    var readCallCount: Int {
        lock.withLock { storedReadCallCount }
    }

    init(
        size: TerminalSize = TerminalSize(columns: 80, rows: 24),
        writeError: PseudoTerminalError? = nil,
        resizeError: PseudoTerminalError? = nil,
        readResults: [FakeReadResult] = []
    ) {
        self.storedSize = size
        self.writeError = writeError
        self.resizeError = resizeError
        self.readResults = readResults
    }

    func write(_ bytes: [UInt8]) throws {
        if let writeError {
            throw writeError
        }

        lock.withLock {
            storedWrites.append(bytes)
        }
    }

    func resize(_ size: TerminalSize) throws {
        if let resizeError {
            throw resizeError
        }

        lock.withLock {
            storedSize = size
            storedResizes.append(size)
        }
    }

    func readAvailableBytes(maxBytes: Int = 4096) throws -> [UInt8] {
        guard maxBytes > 0 else {
            return []
        }

        let result = lock.withLock {
            storedReadCallCount += 1
            guard !readResults.isEmpty else {
                return nil as FakeReadResult?
            }
            return readResults.removeFirst()
        }

        switch result {
        case .bytes(let bytes):
            return Array(bytes.prefix(maxBytes))
        case .empty:
            return []
        case .failure(let error):
            throw error
        case nil:
            return []
        }
    }

    func terminate() {
        lock.withLock {
            storedTerminateCallCount += 1
            storedState = .terminating
        }
    }
}
