import Darwin
import Foundation

public final class KktLock {
    private let path: String
    private let clock: () -> TimeInterval
    private let sleep: (TimeInterval) -> Void
    private var fileDescriptor = KktConstants.invalidFileDescriptor

    public init(path: String, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.clock = clock
        self.sleep = sleep
        self.path = (path as NSString).expandingTildeInPath
    }

    deinit {
        release()
    }

    public func acquire(timeout: TimeInterval) throws {
        guard fileDescriptor == KktConstants.invalidFileDescriptor else { return }
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: KktConstants.lockDirectoryPermissions]
        )
        fileDescriptor = Darwin.open(path, O_CREAT | O_RDWR, KktConstants.lockFilePermissions)
        guard fileDescriptor != KktConstants.invalidFileDescriptor else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        do {
            try waitForLock(timeout: timeout)
        } catch {
            release()
            throw error
        }
    }

    private func waitForLock(timeout: TimeInterval) throws {
        let deadline = clock() + timeout
        while flock(fileDescriptor, LOCK_EX | LOCK_NB) != KktConstants.systemCallSuccess {
            guard errno == EWOULDBLOCK || errno == EINTR else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let remaining = deadline - clock()
            guard remaining > KktConstants.zeroInterval else { throw KktError.busy }
            sleep(min(KktConstants.lockPollInterval, remaining))
        }
    }

    public func release() {
        guard fileDescriptor != KktConstants.invalidFileDescriptor else { return }
        _ = flock(fileDescriptor, LOCK_UN)
        _ = Darwin.close(fileDescriptor)
        fileDescriptor = KktConstants.invalidFileDescriptor
    }
}
