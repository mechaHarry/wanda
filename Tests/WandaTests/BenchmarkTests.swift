import XCTest
@testable import Wanda

@MainActor
final class BenchmarkTests: XCTestCase {
    func testWorkloadGeneratesDeterministicColoredBatches() {
        let workload = MetalStressBenchmarkWorkload(
            identifier: "test-workload",
            lineCount: 3,
            lineWidth: 16,
            linesPerBatch: 2
        )

        let batches = workload.batches()
        let output = batches.joined()
        let stripped = removingANSIEscapes(output).replacingOccurrences(of: "\r\n", with: "\n")
        let lines = stripped.split(separator: "\n", omittingEmptySubsequences: true)

        XCTAssertEqual(batches.count, 2)
        XCTAssertTrue(output.contains("\u{001B}[30;40m"))
        XCTAssertEqual(workload.printableCharacterCount, 48)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.allSatisfy { $0.count == 16 })
        XCTAssertEqual(workload.batches(), batches)
    }

    func testBenchmarkResultComputesRatesAndSummary() {
        let result = MetalStressBenchmarkResult(
            workloadIdentifier: "metal-stress-test",
            lineCount: 10,
            bytesWritten: 200,
            printableCharacters: 100,
            elapsedNanoseconds: 2_000_000_000,
            frameTimestamps: [1_000_000_000, 2_000_000_000, 3_000_000_000]
        )

        XCTAssertEqual(result.elapsedSeconds, 2, accuracy: 0.0001)
        XCTAssertEqual(result.charactersPerSecond, 50, accuracy: 0.0001)
        XCTAssertEqual(result.bytesPerSecond, 100, accuracy: 0.0001)
        XCTAssertEqual(result.framesPerSecond, 1, accuracy: 0.0001)
        XCTAssertTrue(result.summary.contains("workload: metal-stress-test"))
        XCTAssertTrue(result.summary.contains("metal frames: 3"))
    }

    func testBenchmarkViewModelRunsWorkloadAndPrintsSummary() async {
        let workload = MetalStressBenchmarkWorkload(
            identifier: "metal-stress-test",
            lineCount: 4,
            lineWidth: 12,
            linesPerBatch: 1
        )
        let viewModel = BenchmarkTerminalViewModel(workload: workload, columns: 80, rows: 18)

        let result = await viewModel.runForTesting()

        XCTAssertEqual(result.workloadIdentifier, "metal-stress-test")
        XCTAssertEqual(result.lineCount, 4)
        XCTAssertEqual(result.printableCharacters, workload.printableCharacterCount)
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertTrue(visibleText(in: viewModel.snapshot).contains("Wanda Metal Stress Benchmark complete"))
    }

    private func visibleText(in snapshot: TerminalRendererSnapshot) -> String {
        (0..<snapshot.rows).map { row in
            let start = row * snapshot.columns
            let end = min(start + snapshot.columns, snapshot.cells.count)
            return snapshot.cells[start..<end].map(\.character).map(String.init).joined()
        }
        .joined(separator: "\n")
    }

    private func removingANSIEscapes(_ string: String) -> String {
        var result = ""
        var isEscaping = false

        for character in string {
            if character == "\u{001B}" {
                isEscaping = true
                continue
            }

            if isEscaping {
                if character == "m" {
                    isEscaping = false
                }
                continue
            }

            result.append(character)
        }

        return result
    }
}
