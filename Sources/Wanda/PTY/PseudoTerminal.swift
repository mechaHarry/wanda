import Darwin
import Foundation

@_silgen_name("fork")
private func cFork() -> pid_t

protocol PseudoTerminal: AnyObject {
    var currentSize: TerminalSize { get }
    var state: PseudoTerminalState { get }

    func write(_ bytes: [UInt8]) throws
    func resize(_ size: TerminalSize) throws
    func terminate()
    func readAvailableBytes() throws -> [UInt8]
    func readUntilString(_ string: String, timeoutNanoseconds: UInt64) async throws -> String
}

final class PosixPseudoTerminal: PseudoTerminal, @unchecked Sendable {
    private let fdLock = NSLock()
    private let sizeLock = NSLock()
    private let stateLock = NSLock()

    private var masterFileDescriptor: Int32
    private let childProcessID: pid_t
    private var storedSize: TerminalSize
    private var storedState: PseudoTerminalState = .running
    private var cleanupStarted = false

    var currentSize: TerminalSize {
        sizeLock.withLock { storedSize }
    }

    var state: PseudoTerminalState {
        stateLock.withLock { storedState }
    }

    init(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        size: TerminalSize
    ) throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var windowSize = winsize(
            ws_row: size.rows,
            ws_col: size.columns,
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        guard openpty(&master, &slave, nil, nil, &windowSize) == 0 else {
            throw PseudoTerminalError.openFailed(errno: errno)
        }

        guard let executablePointer = strdup(executablePath) else {
            let allocationErrno = errno == 0 ? ENOMEM : errno
            close(master)
            close(slave)
            throw PseudoTerminalError.configureFailed(errno: allocationErrno)
        }

        var argumentPointers = arguments.map { strdup($0) }
        var environmentPointers = environment.map { key, value in strdup("\(key)=\(value)") }

        guard !argumentPointers.contains(where: { $0 == nil }),
              !environmentPointers.contains(where: { $0 == nil })
        else {
            let allocationErrno = errno == 0 ? ENOMEM : errno
            free(executablePointer)
            for pointer in argumentPointers where pointer != nil {
                free(pointer)
            }
            for pointer in environmentPointers where pointer != nil {
                free(pointer)
            }
            close(master)
            close(slave)
            throw PseudoTerminalError.configureFailed(errno: allocationErrno)
        }

        argumentPointers.append(nil)
        environmentPointers.append(nil)

        defer {
            free(executablePointer)
            for pointer in argumentPointers where pointer != nil {
                free(pointer)
            }
            for pointer in environmentPointers where pointer != nil {
                free(pointer)
            }
        }

        let pid = cFork()
        guard pid >= 0 else {
            let forkErrno = errno
            close(master)
            close(slave)
            throw PseudoTerminalError.forkFailed(errno: forkErrno)
        }

        if pid == 0 {
            close(master)

            guard setsid() >= 0 else {
                _exit(127)
            }

            guard ioctl(slave, TIOCSCTTY, 0) >= 0 else {
                _exit(127)
            }

            guard dup2(slave, STDIN_FILENO) >= 0 else {
                _exit(127)
            }
            guard dup2(slave, STDOUT_FILENO) >= 0 else {
                _exit(127)
            }
            guard dup2(slave, STDERR_FILENO) >= 0 else {
                _exit(127)
            }

            if slave > STDERR_FILENO {
                close(slave)
            }

            execve(executablePointer, &argumentPointers, &environmentPointers)
            _exit(127)
        }

        close(slave)

        let flags = fcntl(master, F_GETFL)
        guard flags >= 0, fcntl(master, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            let configureErrno = errno
            close(master)
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
            throw PseudoTerminalError.configureFailed(errno: configureErrno)
        }

        masterFileDescriptor = master
        childProcessID = pid
        storedSize = size
    }

    deinit {
        terminate()
    }

    func write(_ bytes: [UInt8]) throws {
        try ensureRunning()

        var writtenCount = 0
        try fdLock.withLock {
            let fd = try openMasterFileDescriptor()
            while writtenCount < bytes.count {
                let result = bytes.withUnsafeBytes { buffer in
                    Darwin.write(fd, buffer.baseAddress!.advanced(by: writtenCount), bytes.count - writtenCount)
                }

                if result > 0 {
                    writtenCount += result
                    continue
                }

                if result == -1 && errno == EINTR {
                    continue
                }

                if result == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    usleep(1_000)
                    continue
                }

                throw PseudoTerminalError.writeFailed(errno: errno)
            }
        }
    }

    func resize(_ size: TerminalSize) throws {
        var windowSize = winsize(
            ws_row: size.rows,
            ws_col: size.columns,
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        try fdLock.withLock {
            let fd = try openMasterFileDescriptor()
            guard ioctl(fd, TIOCSWINSZ, &windowSize) >= 0 else {
                throw PseudoTerminalError.resizeFailed(errno: errno)
            }
        }

        sizeLock.withLock {
            storedSize = size
        }
    }

    func terminate() {
        let shouldCleanup = stateLock.withLock {
            if cleanupStarted {
                return false
            }
            cleanupStarted = true
            storedState = .terminated
            return true
        }

        guard shouldCleanup else {
            return
        }

        fdLock.withLock {
            if masterFileDescriptor >= 0 {
                close(masterFileDescriptor)
                masterFileDescriptor = -1
            }
        }

        if waitpid(childProcessID, nil, WNOHANG) == childProcessID {
            return
        }

        kill(childProcessID, SIGTERM)

        for _ in 0..<20 {
            if waitpid(childProcessID, nil, WNOHANG) == childProcessID {
                return
            }
            usleep(10_000)
        }

        kill(childProcessID, SIGKILL)
        waitpid(childProcessID, nil, 0)
    }

    func readAvailableBytes() throws -> [UInt8] {
        try ensureRunning()

        var output: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)

        try fdLock.withLock {
            let fd = try openMasterFileDescriptor()

            while true {
                let result = Darwin.read(fd, &buffer, buffer.count)

                if result > 0 {
                    output.append(contentsOf: buffer.prefix(result))
                    continue
                }

                if result == 0 {
                    markTerminated()
                    break
                }

                if errno == EINTR {
                    continue
                }

                if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                }

                if errno == EIO {
                    markTerminated()
                    break
                }

                throw PseudoTerminalError.readFailed(errno: errno)
            }
        }

        return output
    }

    func readUntilString(_ string: String, timeoutNanoseconds: UInt64) async throws -> String {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        var bytes: [UInt8] = []

        while DispatchTime.now().uptimeNanoseconds < deadline {
            bytes.append(contentsOf: try readAvailableBytes())

            let output = String(decoding: bytes, as: UTF8.self)
            if output.contains(string) {
                return output
            }

            if state == .terminated {
                throw PseudoTerminalError.processTerminated
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        throw PseudoTerminalError.timedOut
    }

    private func ensureRunning() throws {
        if state == .terminated {
            throw PseudoTerminalError.processTerminated
        }
    }

    private func openMasterFileDescriptor() throws -> Int32 {
        guard masterFileDescriptor >= 0 else {
            throw PseudoTerminalError.processTerminated
        }
        return masterFileDescriptor
    }

    private func markTerminated() {
        stateLock.withLock {
            storedState = .terminated
        }
    }
}

extension NSLock {
    @discardableResult
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
