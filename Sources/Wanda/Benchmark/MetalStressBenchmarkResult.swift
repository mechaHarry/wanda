import Foundation

struct MetalStressBenchmarkResult: Equatable, Sendable {
    var workloadIdentifier: String
    var lineCount: Int
    var bytesWritten: Int
    var printableCharacters: Int
    var elapsedNanoseconds: UInt64
    var frameTimestamps: [UInt64]

    var elapsedSeconds: Double {
        max(Double(elapsedNanoseconds) / 1_000_000_000, 0.000_001)
    }

    var charactersPerSecond: Double {
        Double(printableCharacters) / elapsedSeconds
    }

    var bytesPerSecond: Double {
        Double(bytesWritten) / elapsedSeconds
    }

    var framesPerSecond: Double {
        guard frameTimestamps.count > 1,
              let first = frameTimestamps.first,
              let last = frameTimestamps.last,
              last > first else {
            return 0
        }

        let frameSeconds = Double(last - first) / 1_000_000_000
        return Double(frameTimestamps.count - 1) / max(frameSeconds, 0.000_001)
    }

    var summary: String {
        [
            "",
            "Wanda Metal Stress Benchmark complete",
            "workload: \(workloadIdentifier)",
            "lines: \(lineCount)",
            "printable characters: \(printableCharacters)",
            "bytes written: \(bytesWritten)",
            String(format: "total print time: %.3f s", elapsedSeconds),
            String(format: "characters/sec: %.0f", charactersPerSecond),
            String(format: "bytes/sec: %.0f", bytesPerSecond),
            "metal frames: \(frameTimestamps.count)",
            String(format: "metal fps: %.1f", framesPerSecond),
            ""
        ].joined(separator: "\r\n")
    }
}
