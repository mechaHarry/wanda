import Foundation

struct MetalStressBenchmarkWorkload: Equatable, Sendable {
    var identifier: String
    var lineCount: Int
    var lineWidth: Int
    var linesPerBatch: Int

    init(
        identifier: String = "metal-stress-v1",
        lineCount: Int = 720,
        lineWidth: Int = 160,
        linesPerBatch: Int = 24
    ) {
        self.identifier = identifier
        self.lineCount = max(1, lineCount)
        self.lineWidth = max(1, lineWidth)
        self.linesPerBatch = max(1, linesPerBatch)
    }

    var printableCharacterCount: Int {
        lineCount * lineWidth
    }

    func batches() -> [String] {
        stride(from: 0, to: lineCount, by: linesPerBatch).map { startLine in
            let endLine = min(startLine + linesPerBatch, lineCount)
            return (startLine..<endLine).map(line).joined()
        }
    }

    func line(_ index: Int) -> String {
        let foreground = 30 + (index % 8)
        let background = 40 + ((index / 3) % 8)
        return "\u{001B}[\(foreground);\(background)m\(lineBody(index))\u{001B}[0m\r\n"
    }

    private func lineBody(_ index: Int) -> String {
        let seed = String(format: "%05d", index)
        let tokens = [
            "WANDA",
            "METAL",
            "0123456789",
            "abcdef",
            "/-\\|",
            "@#%*+=-_",
            seed
        ]
        var body = ""
        var tokenIndex = index % tokens.count

        while body.count < lineWidth {
            body += tokens[tokenIndex]
            tokenIndex = (tokenIndex + 1) % tokens.count
        }

        return String(body.prefix(lineWidth))
    }
}
