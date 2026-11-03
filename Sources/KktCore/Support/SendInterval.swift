import Foundation

public final class SendInterval {
    private let path: String
    private let clock: () -> Date
    private let sleep: (TimeInterval) -> Void

    public init(path: String, clock: @escaping () -> Date = { Date() },
                sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.path = (path as NSString).expandingTildeInPath + KktConstants.lastSendSuffix
        self.clock = clock
        self.sleep = sleep
    }

    public func waitIfNeeded() throws {
        try waitIfNeeded(minimum: KktConstants.minimumSendInterval)
    }

    public func waitIfNeeded(minimum: TimeInterval) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        guard let lastSend = TimeInterval(contents), lastSend.isFinite else { throw KktError.invalidConfig }
        let elapsed = clock().timeIntervalSince1970 - lastSend
        let remaining = minimum - elapsed
        if remaining > KktConstants.zeroInterval { sleep(remaining) }
    }

    public func record() throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
            attributes: [.posixPermissions: KktConstants.directoryPermissions])
        try Data(String(clock().timeIntervalSince1970).utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: KktConstants.filePermissions], ofItemAtPath: path)
    }
}
