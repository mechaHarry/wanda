import XCTest
@testable import Wanda

final class PseudoTerminalTests: XCTestCase {
    func testLaunchesShellAndEchoesInput() async throws {
        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        try pty.write(Array("printf wanda\n".utf8))
        let output = try await pty.readUntilString("wanda", timeoutNanoseconds: 2_000_000_000)

        XCTAssertTrue(output.contains("wanda"))
    }

    func testResizeUpdatesStoredSize() throws {
        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        try pty.resize(TerminalSize(columns: 100, rows: 40))

        XCTAssertEqual(pty.currentSize, TerminalSize(columns: 100, rows: 40))
    }
}
