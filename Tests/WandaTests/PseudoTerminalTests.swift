import XCTest
@testable import Wanda

final class PseudoTerminalTests: XCTestCase {
    func testTerminalSizeStoresPositiveIntValues() {
        let size = TerminalSize(columns: 120, rows: 32)

        let columns: Int = size.columns
        let rows: Int = size.rows

        XCTAssertEqual(columns, 120)
        XCTAssertEqual(rows, 32)
    }

    func testPseudoTerminalErrorExposesRequiredCases() {
        let errors: [PseudoTerminalError] = [
            .openFailed,
            .forkFailed,
            .execFailed,
            .writeFailed(EBADF),
            .readFailed(EBADF),
            .resizeFailed(EBADF),
            .timedOut,
        ]

        for error in errors {
            switch error {
            case .openFailed, .forkFailed, .execFailed, .writeFailed, .readFailed, .resizeFailed, .timedOut:
                break
            }
        }
    }

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

    func testTerminateTransitionsStateToTerminatingOrExited() throws {
        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )

        pty.terminate()

        switch pty.state {
        case .terminating, .exited:
            break
        case .running, .failed:
            XCTFail("Expected terminating or exited state after terminate(), got \(pty.state)")
        }
    }

    func testReadAvailableBytesRespectsMaxBytes() async throws {
        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        try pty.write(Array("printf abcdef\n".utf8))
        _ = try await pty.readUntilString("abcdef", timeoutNanoseconds: 2_000_000_000)

        try pty.write(Array("printf 123456789\n".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)

        let output = try pty.readAvailableBytes(maxBytes: 4)

        XCTAssertLessThanOrEqual(output.count, 4)
    }
}
