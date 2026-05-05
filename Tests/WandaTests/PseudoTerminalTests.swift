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

        let marker = "PROCESS_WANDA_MARKER"
        let command = "printf '\\120\\122\\117\\103\\105\\123\\123\\137\\127\\101\\116\\104\\101\\137\\115\\101\\122\\113\\105\\122'\n"
        XCTAssertFalse(command.contains(marker))

        try pty.write(Array(command.utf8))
        let output = try await pty.readUntilString(marker, timeoutNanoseconds: 2_000_000_000)

        XCTAssertTrue(output.contains(marker))
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

    func testResizeRejectsSizesOutsideWinsizeRangeWithoutChangingStoredSize() throws {
        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        XCTAssertThrowsError(try pty.resize(TerminalSize(columns: Int(UInt16.max) + 1, rows: 24))) { error in
            XCTAssertEqual(error as? PseudoTerminalError, .resizeFailed(EINVAL))
        }
        XCTAssertEqual(pty.currentSize, TerminalSize(columns: 80, rows: 24))
    }

    func testInitializerRejectsSizesOutsideWinsizeRange() {
        XCTAssertThrowsError(try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: Int(UInt16.max) + 1)
        )) { error in
            XCTAssertEqual(error as? PseudoTerminalError, .openFailed)
        }
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

    func testReadUntilStringThrowsWhenCaptureBoundIsExceeded() async throws {
        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        try pty.write(Array("printf 1234567890\n".utf8))

        do {
            _ = try await pty.readUntilString(
                "never-arrives",
                timeoutNanoseconds: 2_000_000_000,
                maxCaptureBytes: 4
            )
            XCTFail("Expected readUntilString to enforce maxCaptureBytes")
        } catch let error as PseudoTerminalError {
            XCTAssertEqual(error, .readFailed(ENOMEM))
        }
    }

    func testReadEOFReapsChildAndLeavesNonRunningState() async throws {
        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh", "-c", "printf done; exit 7"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        _ = try await pty.readUntilString("done", timeoutNanoseconds: 2_000_000_000)

        for _ in 0..<100 where pty.state == .running {
            _ = try pty.readAvailableBytes()
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        switch pty.state {
        case .exited:
            break
        case .running, .terminating, .failed:
            XCTFail("Expected exited state after shell EOF, got \(pty.state)")
        }

        pty.terminate()
        pty.terminate()
    }
}
