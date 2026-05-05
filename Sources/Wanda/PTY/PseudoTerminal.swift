import Darwin
import Foundation
import WandaPTYSpawn

public protocol PseudoTerminal: AnyObject, Sendable {
    var currentSize: TerminalSize { get }
    var state: PseudoTerminalState { get }

    func write(_ bytes: [UInt8]) throws
    func resize(_ size: TerminalSize) throws
    func readAvailableBytes(maxBytes: Int) throws -> [UInt8]
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
    private let writeStallTimeoutNanoseconds: UInt64 = 2_000_000_000

    private enum ReadCleanupAction {
        case none
        case emptyRead
        case eof
    }

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

        guard Self.isValidWinsize(size) else {
            throw PseudoTerminalError.openFailed
        }

        var windowSize = winsize(
            ws_row: UInt16(size.rows),
            ws_col: UInt16(size.columns),
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
        let closeLimit = Self.openFileDescriptorCloseLimit()

        defer {
            free(executablePointer)
            for pointer in argumentPointers where pointer != nil {
                free(pointer)
            }
            for pointer in environmentPointers where pointer != nil {
                free(pointer)
            }
        }

        let pid = argumentPointers.withUnsafeMutableBufferPointer { argvBuffer in
            environmentPointers.withUnsafeMutableBufferPointer { envpBuffer in
                wanda_pty_fork_exec(
                    master,
                    slave,
                    closeLimit,
                    executablePointer,
                    argvBuffer.baseAddress,
                    envpBuffer.baseAddress
                )
            }
        }
        guard pid >= 0 else {
            close(master)
            close(slave)
            throw PseudoTerminalError.forkFailed
        }

        close(slave)

        let flags = fcntl(master, F_GETFL)
        guard flags >= 0, fcntl(master, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            close(master)
            Self.killProcess(pid, signal: SIGKILL)
            _ = Self.waitForProcess(pid, options: 0)
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
        var stallDeadline = DispatchTime.now().uptimeNanoseconds + writeStallTimeoutNanoseconds
        try fdLock.withLock {
            let fd = try openMasterFileDescriptor(closedError: .writeFailed(EBADF))
            while writtenCount < bytes.count {
                let result = bytes.withUnsafeBytes { buffer in
                    Darwin.write(fd, buffer.baseAddress!.advanced(by: writtenCount), bytes.count - writtenCount)
                }

                if result > 0 {
                    writtenCount += result
                    stallDeadline = DispatchTime.now().uptimeNanoseconds + writeStallTimeoutNanoseconds
                    continue
                }

                if result == -1 && errno == EINTR {
                    continue
                }

                if result == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    let writeErrno = errno
                    if DispatchTime.now().uptimeNanoseconds >= stallDeadline {
                        throw PseudoTerminalError.writeFailed(writeErrno)
                    }
                    usleep(1_000)
                    continue
                }

                throw PseudoTerminalError.writeFailed(errno)
            }
        }
    }

    public func resize(_ size: TerminalSize) throws {
        guard Self.isValidWinsize(size) else {
            throw PseudoTerminalError.resizeFailed(EINVAL)
        }

        var windowSize = winsize(
            ws_row: UInt16(size.rows),
            ws_col: UInt16(size.columns),
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
            switch storedState {
            case .exited, .failed:
                return false
            case .running, .terminating:
                break
            }
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

        switch Self.waitForProcess(childProcessID, options: WNOHANG) {
        case .exited(let status):
            setState(.exited(status))
            return
        case .alreadyReaped:
            setState(.exited(0))
            return
        case .failed(let waitErrno):
            setState(.failed("waitpid failed with errno \(waitErrno)"))
            return
        case .stillRunning:
            break
        }

        switch Self.killProcess(childProcessID, signal: SIGTERM) {
        case .sent, .alreadyExited:
            break
        case .failed(let killErrno):
            setState(.failed("kill failed with errno \(killErrno)"))
            return
        }

        for _ in 0..<20 {
            switch Self.waitForProcess(childProcessID, options: WNOHANG) {
            case .exited(let status):
                setState(.exited(status))
                return
            case .alreadyReaped:
                setState(.exited(0))
                return
            case .failed(let waitErrno):
                setState(.failed("waitpid failed with errno \(waitErrno)"))
                return
            case .stillRunning:
                break
            }
            usleep(10_000)
        }

        switch Self.killProcess(childProcessID, signal: SIGKILL) {
        case .sent, .alreadyExited:
            break
        case .failed(let killErrno):
            setState(.failed("kill failed with errno \(killErrno)"))
            return
        }

        switch Self.waitForProcess(childProcessID, options: 0) {
        case .exited(let status):
            setState(.exited(status))
        case .alreadyReaped:
            setState(.exited(0))
        case .failed(let waitErrno):
            setState(.failed("waitpid failed with errno \(waitErrno)"))
        case .stillRunning:
            setState(.failed("waitpid unexpectedly reported a running child"))
        }
    }

    public func readAvailableBytes(maxBytes: Int = 4096) throws -> [UInt8] {
        guard maxBytes > 0 else {
            return []
        }

        switch state {
        case .running:
            break
        case .terminating:
            reapChildNonblocking()
            return []
        case .exited, .failed:
            return []
        }

        var output: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: min(maxBytes, 4096))
        var cleanupAction = ReadCleanupAction.none

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
                    closeMasterFileDescriptorWithLockHeld()
                    cleanupAction = .eof
                    break
                }

                if errno == EINTR {
                    continue
                }

                if errno == EAGAIN || errno == EWOULDBLOCK {
                    cleanupAction = .emptyRead
                    break
                }

                if errno == EIO {
                    closeMasterFileDescriptorWithLockHeld()
                    cleanupAction = .eof
                    break
                }

                throw PseudoTerminalError.readFailed(errno)
            }
        }

        switch cleanupAction {
        case .none:
            break
        case .emptyRead:
            reapChildNonblocking(closeMasterOnExit: true)
        case .eof:
            reapChildAfterEOF()
        }

        return output
    }

    public func readUntilString(
        _ string: String,
        timeoutNanoseconds: UInt64,
        maxCaptureBytes: Int = 1_048_576
    ) async throws -> String {
        guard maxCaptureBytes > 0 else {
            throw PseudoTerminalError.readFailed(ENOMEM)
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        var bytes: [UInt8] = []

        while DispatchTime.now().uptimeNanoseconds < deadline {
            let availableBytes = try readAvailableBytes()
            guard bytes.count + availableBytes.count <= maxCaptureBytes else {
                throw PseudoTerminalError.readFailed(ENOMEM)
            }
            bytes.append(contentsOf: availableBytes)

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

    private func reapChildNonblocking(closeMasterOnExit: Bool = false) {
        switch Self.waitForProcess(childProcessID, options: WNOHANG) {
        case .exited(let status):
            if closeMasterOnExit {
                closeMasterFileDescriptor()
            }
            setState(.exited(status))
        case .alreadyReaped:
            if closeMasterOnExit {
                closeMasterFileDescriptor()
            }
            setState(.exited(0))
        case .failed(let waitErrno):
            setState(.failed("waitpid failed with errno \(waitErrno)"))
        case .stillRunning:
            break
        }
    }

    private func closeMasterFileDescriptor() {
        fdLock.withLock {
            closeMasterFileDescriptorWithLockHeld()
        }
    }

    private func closeMasterFileDescriptorWithLockHeld() {
        if masterFileDescriptor >= 0 {
            close(masterFileDescriptor)
            masterFileDescriptor = -1
        }
    }

    private func reapChildAfterEOF() {
        switch Self.waitForProcess(childProcessID, options: WNOHANG) {
        case .exited(let status):
            setState(.exited(status))
        case .alreadyReaped:
            setState(.exited(0))
        case .failed(let waitErrno):
            setState(.failed("waitpid failed with errno \(waitErrno)"))
        case .stillRunning:
            setState(.terminating)
        }
    }

    private func setState(_ state: PseudoTerminalState) {
        stateLock.withLock {
            storedState = state
        }
    }

    private static func isValidWinsize(_ size: TerminalSize) -> Bool {
        size.columns <= Int(UInt16.max) && size.rows <= Int(UInt16.max)
    }

    private static func waitForProcess(_ processID: pid_t, options: Int32) -> WaitResult {
        var status: Int32 = 0

        while true {
            let result = waitpid(processID, &status, options)

            if result == processID {
                return .exited(status)
            }

            if result == 0 {
                return .stillRunning
            }

            if errno == EINTR {
                continue
            }

            if errno == ECHILD {
                return .alreadyReaped
            }

            return .failed(errno)
        }
    }

    @discardableResult
    private static func killProcess(_ processID: pid_t, signal: Int32) -> KillResult {
        while true {
            if kill(processID, signal) == 0 {
                return .sent
            }

            if errno == EINTR {
                continue
            }

            if errno == ESRCH {
                return .alreadyExited
            }

            return .failed(errno)
        }
    }

    private static func openFileDescriptorCloseLimit() -> Int32 {
        let openMax = sysconf(_SC_OPEN_MAX)
        if openMax > 0 && openMax <= Int(Int32.max) {
            return Int32(openMax)
        }

        return Int32(getdtablesize())
    }
}

private enum WaitResult {
    case exited(Int32)
    case stillRunning
    case alreadyReaped
    case failed(Int32)
}

private enum KillResult {
    case sent
    case alreadyExited
    case failed(Int32)
}

extension NSLock {
    @discardableResult
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
