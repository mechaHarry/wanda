import Foundation
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
        case .terminating, .exited, .signaled:
            break
        case .running, .failed:
            XCTFail("Expected non-running state after terminate(), got \(pty.state)")
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
        let markerPath = "/tmp/wanda-pty-eof-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: markerPath) }

        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh", "-c", "printf done; exec </dev/null >/dev/null 2>/dev/null; : > \(markerPath); exit 7"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        _ = try await pty.readUntilString("done", timeoutNanoseconds: 2_000_000_000)
        try await waitForFile(atPath: markerPath)
        _ = try pty.readAvailableBytes()

        try await waitForExitedState(pty)

        switch pty.state {
        case .exited(let status):
            XCTAssertEqual(status, 7)
        case .running, .terminating, .signaled, .failed:
            XCTFail("Expected exited state after shell EOF, got \(pty.state)")
        }

        pty.terminate()
        pty.terminate()
    }

    func testSignalTerminationReportsSignalInsteadOfExitStatus() async throws {
        let pty = try PosixPseudoTerminal(
            executablePath: "/usr/bin/perl",
            arguments: ["perl", "-e", "$| = 1; print \"done\"; select(undef, undef, undef, 0.05); kill 'KILL', $$;"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        _ = try await pty.readUntilString("done", timeoutNanoseconds: 2_000_000_000)
        try await waitForSignalState(pty)

        switch pty.state {
        case .signaled(let signal):
            XCTAssertEqual(signal, SIGKILL)
        case .running, .terminating, .exited, .failed:
            XCTFail("Expected signaled state after child killed itself, got \(pty.state)")
        }
    }

    func testReadEOFWaitsForNaturalChildExitWithoutLeavingTerminatingState() async throws {
        let markerPath = "/tmp/wanda-pty-eof-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: markerPath) }

        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh", "-c", "printf done; exec </dev/null >/dev/null 2>/dev/null; : > \(markerPath); exit 7"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        _ = try await pty.readUntilString("done", timeoutNanoseconds: 2_000_000_000)
        try await waitForFile(atPath: markerPath)
        _ = try pty.readAvailableBytes()

        try await waitForExitedState(pty)

        switch pty.state {
        case .exited:
            break
        case .running, .terminating, .signaled, .failed:
            XCTFail("Expected EOF cleanup to reap child instead of leaving \(pty.state)")
        }

        XCTAssertNoThrow(try pty.readAvailableBytes())
    }

    func testReadEOFReturnsPromptlyWhenChildClosesPTYBeforeExit() async throws {
        let markerPath = "/tmp/wanda-pty-eof-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: markerPath) }

        let pty = try PosixPseudoTerminal(
            executablePath: "/usr/bin/perl",
            arguments: [
                "perl",
                "-e",
                "print \"done\"; close STDIN; close STDOUT; close STDERR; open(my $fh, '>', $ARGV[0]) or exit 2; close $fh; select(undef, undef, undef, 0.4); exit 7;",
                markerPath,
            ],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        _ = try await pty.readUntilString("done", timeoutNanoseconds: 2_000_000_000)
        try await waitForFile(atPath: markerPath)

        try await waitForEOFReadWithoutBlocking(pty)

        try await waitForExitedState(pty, timeoutNanoseconds: 1_000_000_000)
    }

    func testTerminateReturnsPromptlyAfterEOFBeforeDelayedExit() async throws {
        let markerPath = "/tmp/wanda-pty-eof-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: markerPath) }

        let pty = try PosixPseudoTerminal(
            executablePath: "/usr/bin/perl",
            arguments: [
                "perl",
                "-e",
                "print \"done\"; close STDIN; close STDOUT; close STDERR; open(my $fh, '>', $ARGV[0]) or exit 2; close $fh; select(undef, undef, undef, 1.0); exit 7;",
                markerPath,
            ],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        _ = try await pty.readUntilString("done", timeoutNanoseconds: 2_000_000_000)
        try await waitForFile(atPath: markerPath)
        try await waitForEOFReadWithoutBlocking(pty)

        let terminateReturned = expectation(description: "terminate returns while delayed child is still alive")
        let terminateTask = Task {
            pty.terminate()
            terminateReturned.fulfill()
        }

        await fulfillment(of: [terminateReturned], timeout: 0.3)
        _ = await terminateTask.result

        switch pty.state {
        case .terminating, .exited, .signaled:
            break
        case .running, .failed:
            XCTFail("Expected terminate to leave a non-running state, got \(pty.state)")
        }
    }

    private func waitForFile(atPath path: String) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if FileManager.default.fileExists(atPath: path) {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTFail("Timed out waiting for \(path)")
    }

    private func waitForEOFReadWithoutBlocking(_ pty: PosixPseudoTerminal) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 300_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let readReturned = expectation(description: "EOF read returns without waiting for child exit")
            let readTask = Task {
                XCTAssertNoThrow(try pty.readAvailableBytes())
                readReturned.fulfill()
            }

            await fulfillment(of: [readReturned], timeout: 0.05)
            _ = await readTask.result

            switch pty.state {
            case .terminating, .exited, .signaled:
                return
            case .failed(let message):
                XCTFail("Expected EOF read to mark terminating or exited, got failed: \(message)")
                return
            case .running:
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }

        XCTFail("Timed out waiting for EOF read to mark a non-running state, got \(pty.state)")
    }

    private func waitForExitedState(
        _ pty: PosixPseudoTerminal,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            _ = try pty.readAvailableBytes()

            switch pty.state {
            case .exited:
                return
            case .failed(let message):
                XCTFail("Expected exited state, got failed: \(message)")
                return
            case .running, .terminating:
                break
            case .signaled(let signal):
                XCTFail("Expected exited state, got signal \(signal)")
                return
            }

            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTFail("Timed out waiting for exited state, got \(pty.state)")
    }

    private func waitForSignalState(
        _ pty: PosixPseudoTerminal,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            _ = try pty.readAvailableBytes()

            switch pty.state {
            case .signaled:
                return
            case .failed(let message):
                XCTFail("Expected signaled state, got failed: \(message)")
                return
            case .running, .terminating, .exited:
                break
            }

            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTFail("Timed out waiting for signaled state, got \(pty.state)")
    }
}
