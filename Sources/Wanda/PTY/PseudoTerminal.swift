import Darwin
import Foundation

@_silgen_name("fork")
private func cFork() -> pid_t

public protocol PseudoTerminal: AnyObject, Sendable {
    var currentSize: TerminalSize { get }
    var state: PseudoTerminalState { get }

    func write(_ bytes: [UInt8]) throws
    func resize(_ size: TerminalSize) throws
    func terminate()
}

public final class PosixPseudoTerminal: PseudoTerminal, @unchecked Sendable {
    private let fdLock = NSLock()
    private let sizeLock = NSLock()
    private let stateLock = NSLock()

    private var masterFileDescriptor: Int32
    private let childProcessID: pid_t
    private var storedSize: TerminalSize
    private var storedState: PseudoTerminalState = .running
    private var cleanupStarted = false

    public var currentSize: TerminalSize {
        sizeLock.withLock { storedSize }
    }

    public var state: PseudoTerminalState {
        stateLock.withLock { storedState }
    }

    public init(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        size: TerminalSize
    ) throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var windowSize = winsize(
            ws_row: UInt16(clamping: size.rows),
            ws_col: UInt16(clamping: size.columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        guard openpty(&master, &slave, nil, nil, &windowSize) == 0 else {
            throw PseudoTerminalError.openFailed
        }

        guard let executablePointer = strdup(executablePath) else {
            close(master)
            close(slave)
            throw PseudoTerminalError.execFailed
        }

        var argumentPointers = arguments.map { strdup($0) }
        var environmentPointers = environment.map { key, value in strdup("\(key)=\(value)") }

        guard !argumentPointers.contains(where: { $0 == nil }),
              !environmentPointers.contains(where: { $0 == nil })
        else {
            free(executablePointer)
            for pointer in argumentPointers where pointer != nil {
                free(pointer)
            }
            for pointer in environmentPointers where pointer != nil {
                free(pointer)
            }
            close(master)
            close(slave)
            throw PseudoTerminalError.execFailed
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
            close(master)
            close(slave)
            throw PseudoTerminalError.forkFailed
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
            close(master)
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
            throw PseudoTerminalError.openFailed
        }

        masterFileDescriptor = master
        childProcessID = pid
        storedSize = size
    }

    deinit {
        terminate()
    }

    public func write(_ bytes: [UInt8]) throws {
        try ensureCanWrite()

        var writtenCount = 0
        try fdLock.withLock {
            let fd = try openMasterFileDescriptor(closedError: .writeFailed(EBADF))
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

                throw PseudoTerminalError.writeFailed(errno)
            }
        }
    }

    public func resize(_ size: TerminalSize) throws {
        var windowSize = winsize(
            ws_row: UInt16(clamping: size.rows),
            ws_col: UInt16(clamping: size.columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        try fdLock.withLock {
            let fd = try openMasterFileDescriptor(closedError: .resizeFailed(EBADF))
            guard ioctl(fd, TIOCSWINSZ, &windowSize) >= 0 else {
                throw PseudoTerminalError.resizeFailed(errno)
            }
        }

        sizeLock.withLock {
            storedSize = size
        }
    }

    public func terminate() {
        let shouldCleanup = stateLock.withLock {
            if cleanupStarted {
                return false
            }
            cleanupStarted = true
            storedState = .terminating
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

        var status: Int32 = 0
        if waitpid(childProcessID, &status, WNOHANG) == childProcessID {
            setState(.exited(status))
            return
        }

        kill(childProcessID, SIGTERM)

        for _ in 0..<20 {
            status = 0
            if waitpid(childProcessID, &status, WNOHANG) == childProcessID {
                setState(.exited(status))
                return
            }
            usleep(10_000)
        }

        kill(childProcessID, SIGKILL)
        status = 0
        if waitpid(childProcessID, &status, 0) == childProcessID {
            setState(.exited(status))
        } else {
            setState(.failed("waitpid failed with errno \(errno)"))
        }
    }

    public func readAvailableBytes(maxBytes: Int = 4096) throws -> [UInt8] {
        try ensureCanRead()

        guard maxBytes > 0 else {
            return []
        }

        var output: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: min(maxBytes, 4096))

        try fdLock.withLock {
            let fd = try openMasterFileDescriptor(closedError: .readFailed(EBADF))

            while true {
                let remainingByteCount = maxBytes - output.count
                if remainingByteCount <= 0 {
                    break
                }

                let readByteCount = min(buffer.count, remainingByteCount)
                let result = Darwin.read(fd, &buffer, readByteCount)

                if result > 0 {
                    output.append(contentsOf: buffer.prefix(result))
                    continue
                }

                if result == 0 {
                    setState(.terminating)
                    break
                }

                if errno == EINTR {
                    continue
                }

                if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                }

                if errno == EIO {
                    setState(.terminating)
                    break
                }

                throw PseudoTerminalError.readFailed(errno)
            }
        }

        return output
    }

    public func readUntilString(_ string: String, timeoutNanoseconds: UInt64) async throws -> String {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        var bytes: [UInt8] = []

        while DispatchTime.now().uptimeNanoseconds < deadline {
            bytes.append(contentsOf: try readAvailableBytes())

            let output = String(decoding: bytes, as: UTF8.self)
            if output.contains(string) {
                return output
            }

            if state != .running {
                throw PseudoTerminalError.readFailed(EBADF)
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        throw PseudoTerminalError.timedOut
    }

    private func ensureCanRead() throws {
        if state != .running {
            throw PseudoTerminalError.readFailed(EBADF)
        }
    }

    private func ensureCanWrite() throws {
        if state != .running {
            throw PseudoTerminalError.writeFailed(EBADF)
        }
    }

    private func openMasterFileDescriptor(closedError: PseudoTerminalError) throws -> Int32 {
        guard masterFileDescriptor >= 0 else {
            throw closedError
        }
        return masterFileDescriptor
    }

    private func setState(_ state: PseudoTerminalState) {
        stateLock.withLock {
            storedState = state
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
