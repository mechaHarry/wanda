import Foundation
import SwiftUI

@MainActor
final class BenchmarkTerminalViewModel: ObservableObject {
    @Published private(set) var snapshot: TerminalRendererSnapshot
    @Published private(set) var result: MetalStressBenchmarkResult?
    @Published private(set) var isRunning = false

    private let workload: MetalStressBenchmarkWorkload
    private var parser: any TerminalParser
    private var model: TerminalModel
    private var task: Task<Void, Never>?
    private var frameTimestamps: [UInt64] = []

    init(
        workload: MetalStressBenchmarkWorkload = MetalStressBenchmarkWorkload(),
        columns: Int = 120,
        rows: Int = 36
    ) {
        self.workload = workload
        self.parser = SwiftTerminalParser()
        self.model = TerminalModel(columns: columns, rows: rows, scrollbackLimit: 4_000)
        self.snapshot = TerminalRendererSnapshot(model: model)
        append("Wanda Metal Stress Benchmark\r\n")
        append("workload: \(workload.identifier)\r\n\r\n")
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard task == nil else {
            return
        }

        task = Task { [weak self] in
            _ = await self?.runBenchmark()
        }
    }

    func resize(columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else {
            return
        }

        model.resize(columns: columns, rows: rows)
        snapshot = TerminalRendererSnapshot(model: model)
    }

    func framePresented(at timestamp: UInt64) {
        frameTimestamps.append(timestamp)
        if frameTimestamps.count > 2_000 {
            frameTimestamps.removeFirst(frameTimestamps.count - 2_000)
        }
    }

    @discardableResult
    func runForTesting() async -> MetalStressBenchmarkResult {
        await runBenchmark()
    }

    private func runBenchmark() async -> MetalStressBenchmarkResult {
        guard !isRunning else {
            return result ?? emptyResult()
        }

        isRunning = true
        result = nil
        frameTimestamps = []

        let start = DispatchTime.now().uptimeNanoseconds
        var bytesWritten = 0
        for batch in workload.batches() {
            bytesWritten += batch.utf8.count
            append(batch)
            await Task.yield()
        }
        await Task.yield()
        let elapsed = DispatchTime.now().uptimeNanoseconds - start

        let result = MetalStressBenchmarkResult(
            workloadIdentifier: workload.identifier,
            lineCount: workload.lineCount,
            bytesWritten: bytesWritten,
            printableCharacters: workload.printableCharacterCount,
            elapsedNanoseconds: elapsed,
            frameTimestamps: frameTimestamps
        )
        self.result = result
        append(result.summary)
        isRunning = false
        task = nil
        return result
    }

    private func append(_ string: String) {
        let events = parser.parse(Array(string.utf8))
        for event in events {
            model.apply(event)
        }
        snapshot = TerminalRendererSnapshot(model: model)
    }

    private func emptyResult() -> MetalStressBenchmarkResult {
        MetalStressBenchmarkResult(
            workloadIdentifier: workload.identifier,
            lineCount: workload.lineCount,
            bytesWritten: 0,
            printableCharacters: 0,
            elapsedNanoseconds: 1,
            frameTimestamps: []
        )
    }
}
