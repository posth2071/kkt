import Foundation

public enum DeviceInfo {
    public static func platformUUID(
        run: (_ executable: String, _ arguments: [String]) throws -> Data = runProcess
    ) throws -> String {
        let data = try run(KktConstants.Device.ioregPath, KktConstants.Device.ioregArguments)
        let output = String(decoding: data, as: UTF8.self)
        guard let entry = output.range(of: KktConstants.Device.uuidPattern, options: .regularExpression),
              let uuid = output[entry].range(of: KktConstants.Device.uuidValuePattern, options: .regularExpression) else {
            throw KktError.notFound(KktConstants.Device.uuidResource)
        }
        return String(output[uuid])
    }

    public static func runProcess(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == KktConstants.zero else {
            throw KktError.notFound(KktConstants.Device.uuidResource)
        }
        return data
    }

    public static var preferencesPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(KktConstants.Device.preferences).path
    }

    public static var containerPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(KktConstants.Device.container).path
    }

    public static var containerPreferencesPath: String {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(KktConstants.Device.containerPreferences)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let name = files.sorted().first {
            $0.hasPrefix(KktConstants.Device.plistPrefix) && $0.hasSuffix(KktConstants.Device.plistExtension)
                && $0 != KktConstants.Device.plistName
        } ?? KktConstants.Device.plistName
        return directory.appendingPathComponent(name).path
    }

    public static func activeAccountHash(
        paths: [String] = [containerPreferencesPath, preferencesPath],
        read: (String) throws -> Data = { try Data(contentsOf: URL(fileURLWithPath: $0)) }
    ) -> String? {
        for path in paths {
            guard let data = try? read(path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let hash = activeAccountHash(from: plist) else { continue }
            return hash
        }
        return nil
    }

    public static func activeAccountHash(from plist: [String: Any]) -> String? {
        for key in plist.keys.sorted() where key.hasPrefix(UserIdRecovery.plistKeyPrefix) {
            let hash = String(key.dropFirst(UserIdRecovery.plistKeyPrefix.count))
            guard hash != KktConstants.Crypto.emptyAccountHash,
                  hash.count == KktConstants.Crypto.hashHexLength,
                  hash.allSatisfy(\.isHexDigit),
                  let revision = plist[key] as? NSNumber,
                  revision.doubleValue != Double(KktConstants.zero) else { continue }
            return hash
        }
        return nil
    }

    public static func discoverDatabaseFile(in directory: String = containerPath) -> String? {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        guard let file = files.sorted().first(where: {
            $0.range(of: KktConstants.Device.databasePattern, options: .regularExpression) != nil
        }) else { return nil }
        return URL(fileURLWithPath: directory).appendingPathComponent(file).path
    }
}
