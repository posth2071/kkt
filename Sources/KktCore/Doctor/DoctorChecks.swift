import AppKit
import ApplicationServices
import CSQLCipher
import Darwin
import Foundation

public struct DoctorChecks {
    public enum FileAccess { case readable, missing, denied }
    public enum LockState { case available, busy, unavailable }

    public struct Probes {
        public var fullDiskAccess: () -> FileAccess
        public var accessibility: () -> Bool
        public var screenRecording: () -> Bool
        public var sqlcipher: () -> String?
        public var databaseKey: () -> Bool
        public var runningPid: () -> pid_t?
        public var version: (pid_t) -> String?
        public var ui: (pid_t) -> AXIdentifierTable.Snapshot?
        public var lock: (String) -> LockState
        public var frontmost: () -> Bool

        public init(fullDiskAccess: @escaping () -> FileAccess, accessibility: @escaping () -> Bool,
                    screenRecording: @escaping () -> Bool, sqlcipher: @escaping () -> String?,
                    databaseKey: @escaping () -> Bool, runningPid: @escaping () -> pid_t?,
                    version: @escaping (pid_t) -> String?, ui: @escaping (pid_t) -> AXIdentifierTable.Snapshot?,
                    lock: @escaping (String) -> LockState, frontmost: @escaping () -> Bool) {
            self.fullDiskAccess = fullDiskAccess
            self.accessibility = accessibility
            self.screenRecording = screenRecording
            self.sqlcipher = sqlcipher
            self.databaseKey = databaseKey
            self.runningPid = runningPid
            self.version = version
            self.ui = ui
            self.lock = lock
            self.frontmost = frontmost
        }

        public static func live(config: KktConfig?) -> Self {
            Self(fullDiskAccess: DoctorChecks.fileAccess, accessibility: AXIsProcessTrusted,
                 screenRecording: CGPreflightScreenCaptureAccess, sqlcipher: DoctorChecks.cipherVersion,
                 databaseKey: {
                     guard let config, let database = try? KakaoDatabase.open(config: config) else { return false }
                     database.close()
                     return true
                 }, runningPid: KakaoApp.runningPid, version: { pid in
                     guard let url = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return nil }
                     return Bundle(url: url)?.object(forInfoDictionaryKey: KktConstants.Doctor.bundleVersionKey) as? String
                 }, ui: AXIdentifierTable.observe, lock: DoctorChecks.lockState, frontmost: {
                     NSWorkspace.shared.frontmostApplication?.bundleIdentifier == KakaoApp.bundleId
                 })
        }
    }

    private let config: KktConfig?
    private let probes: Probes

    public init(config: KktConfig?, probes: Probes) {
        self.config = config
        self.probes = probes
    }

    public func run(executablePath: String) -> DoctorReport {
        typealias C = KktConstants.Doctor
        let disk = probes.fullDiskAccess()
        let accessibility = probes.accessibility()
        let screenRecording = probes.screenRecording()
        let cipher = probes.sqlcipher()
        let validUser = (config?.userId ?? KktConstants.zero) > KktConstants.zero
        var checks: [DoctorCheck] = []
        switch disk {
        case .readable: checks.append(.init(id: C.fullDiskAccess, status: .ok, detail: C.readable))
        case .missing: checks.append(.init(id: C.fullDiskAccess, status: .warn, detail: C.missingDatabase, fix: C.runningFix))
        case .denied: checks.append(.init(id: C.fullDiskAccess, status: .fail, detail: C.denied, fix: C.diskFix))
        }
        checks += [
            permission(C.accessibility, granted: accessibility, fix: C.accessibilityFix),
            permission(C.screenRecording, granted: screenRecording, fix: C.screenFix),
            .init(id: C.sqlcipher, status: cipher == nil ? .fail : .ok,
                  detail: cipher ?? C.missingSQLCipher, fix: cipher == nil ? C.sqlcipherFix : nil),
            .init(id: C.userId, status: validUser ? .ok : .fail, detail: validUser ? C.userConfigured : C.userMissing,
                  fix: validUser ? nil : C.userFix),
        ]
        if disk == .readable, cipher != nil, validUser {
            let valid = probes.databaseKey()
            checks.append(.init(id: C.databaseKey, status: valid ? .ok : .fail,
                                detail: valid ? C.keyValid : C.keyInvalid, fix: valid ? nil : C.databaseFix))
        } else {
            checks.append(.init(id: C.databaseKey, status: .warn, detail: C.keySkipped, fix: C.databaseFix))
        }
        let pid = probes.runningPid()
        checks.append(.init(id: C.running, status: pid == nil ? .fail : .ok,
                            detail: pid == nil ? C.notRunning : C.isRunning, fix: pid == nil ? C.runningFix : nil))
        let version = pid.flatMap(probes.version)
        let verified = version.map { config?.verifiedKakaoVersions.contains($0) == true } ?? false
        checks.append(.init(id: C.version, status: verified ? .ok : .warn,
                            detail: version.map { (verified ? C.verifiedPrefix : C.unverifiedPrefix) + $0 } ?? C.unknownVersion,
                            fix: verified ? nil : C.versionFix))
        let snapshot = accessibility ? pid.flatMap(probes.ui) : nil
        checks += uiChecks(snapshot)
        switch probes.lock(config?.lockPath ?? KktConstants.lockPath) {
        case .available: checks.append(.init(id: C.lock, status: .ok, detail: C.lockAvailable))
        case .busy: checks.append(.init(id: C.lock, status: .warn, detail: C.lockBusy, fix: C.lockBusyFix))
        case .unavailable: checks.append(.init(id: C.lock, status: .fail, detail: C.lockUnavailable, fix: C.lockFix))
        }
        if let snapshot {
            let count = snapshot.windows.filter { $0.identifier != KktConstants.mainWindowIdentifier }.count
            checks.append(.init(id: C.userWindows, status: count > KktConstants.zero ? .warn : .ok,
                                detail: C.windowCountPrefix + String(count), fix: count > KktConstants.zero ? C.userWindowsFix : nil))
        } else {
            checks.append(.init(id: C.userWindows, status: .warn, detail: C.windowCountUnknown, fix: C.accessibilityFix))
        }
        checks.append(.init(id: C.frontmost, status: .ok, detail: probes.frontmost() ? C.frontmostTrue : C.frontmostFalse))
        return DoctorReport(executablePath: executablePath, checks: checks)
    }

    private func permission(_ id: String, granted: Bool, fix: String) -> DoctorCheck {
        .init(id: id, status: granted ? .ok : .fail,
              detail: granted ? KktConstants.Doctor.granted : KktConstants.Doctor.notGranted, fix: granted ? nil : fix)
    }

    private func uiChecks(_ snapshot: AXIdentifierTable.Snapshot?) -> [DoctorCheck] {
        typealias C = KktConstants.Doctor
        let hasMain = snapshot?.windows.contains { $0.identifier == KktConstants.mainWindowIdentifier } == true
        var checks = [DoctorCheck(id: C.mainWindow, status: hasMain ? .ok : .warn,
                                  detail: hasMain ? C.mainPresent : C.mainMissing, fix: hasMain ? nil : C.mainWindowFix)]
        guard hasMain, let snapshot else {
            checks.append(.init(id: C.axIdentifiers, status: .warn, detail: C.axUnavailable, fix: C.axFix))
            return checks
        }
        let missing = AXIdentifierTable.missing(in: snapshot)
        checks.append(.init(id: C.axIdentifiers, status: missing.isEmpty ? .ok : .warn,
                            detail: missing.isEmpty ? C.axMatched : C.axMissingPrefix + missing.joined(separator: C.listSeparator),
                            fix: missing.isEmpty ? nil : C.axFix))
        return checks
    }

    static func fileAccess() -> FileAccess {
        let directory = URL(fileURLWithPath: DeviceInfo.containerPath)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard let file = files.first(where: {
                $0.lastPathComponent.range(of: KktConstants.Device.databasePattern, options: .regularExpression) != nil
            }) else { return .missing }
            let handle = try FileHandle(forReadingFrom: file)
            try handle.close()
            return .readable
        } catch CocoaError.fileNoSuchFile { return .missing }
        catch { return .denied }
    }

    static func cipherVersion() -> String? {
        var handle: OpaquePointer?
        guard sqlite3_open(KktConstants.Doctor.memoryDatabase, &handle) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, KktConstants.Doctor.cipherVersionQuery,
                                 KktConstants.Database.nullTerminated, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let version = sqlite3_column_text(statement, KktConstants.zeroColumn) else { return nil }
        return String(cString: version)
    }

    static func lockState(path: String) -> LockState {
        let descriptor = Darwin.open(path, O_RDONLY)
        guard descriptor != KktConstants.invalidFileDescriptor else {
            return errno == ENOENT ? .available : .unavailable
        }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_SH | LOCK_NB) == KktConstants.systemCallSuccess else {
            return errno == EWOULDBLOCK ? .busy : .unavailable
        }
        _ = flock(descriptor, LOCK_UN)
        return .available
    }
}
