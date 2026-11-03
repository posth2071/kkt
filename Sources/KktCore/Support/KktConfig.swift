import Darwin
import Foundation

public struct KktConfig: Codable, Equatable, Sendable {
    public var userId: Int?
    public var lockPath: String
    public var verifiedKakaoVersions: [String]

    public init(userId: Int? = nil, lockPath: String = KktConstants.lockPath, verifiedKakaoVersions: [String] = []) {
        self.userId = userId
        self.lockPath = (lockPath as NSString).expandingTildeInPath
        self.verifiedKakaoVersions = verifiedKakaoVersions
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            userId: try values.decodeIfPresent(Int.self, forKey: .userId),
            lockPath: try values.decodeIfPresent(String.self, forKey: .lockPath) ?? KktConstants.lockPath,
            verifiedKakaoVersions: try values.decodeIfPresent([String].self, forKey: .verifiedKakaoVersions) ?? []
        )
    }

    public static func load(path: String = KktConstants.configPath, environment: [String: String]) throws -> KktConfig {
        let expandedPath = (path as NSString).expandingTildeInPath
        var config = KktConfig()
        if FileManager.default.fileExists(atPath: expandedPath) {
            config = try JSONDecoder().decode(KktConfig.self, from: Data(contentsOf: URL(fileURLWithPath: expandedPath)))
        }
        if let value = environment[KktConstants.userIdEnv] {
            guard let id = Int(value), id > KktConstants.zero else { throw KktError.invalidConfig }
            config.userId = id
        }
        if let id = config.userId, id <= KktConstants.zero { throw KktError.invalidConfig }
        return config
    }

    public static func save(_ config: KktConfig, path: String = KktConstants.configPath) throws {
        let destination = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: KktConstants.directoryPermissions])
        let temporary = directory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                             attributes: [.posixPermissions: KktConstants.filePermissions]) else {
            throw KktError.invalidConfig
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try JSONEncoder().encode(config).write(to: temporary)
        guard chmod(temporary.path, mode_t(KktConstants.filePermissions)) == KktConstants.zero,
              rename(temporary.path, destination.path) == KktConstants.zero else { throw KktError.invalidConfig }
    }
}
