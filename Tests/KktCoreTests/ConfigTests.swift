import CSQLCipher
import Foundation
import XCTest
@testable import KktCore

final class ConfigTests: XCTestCase {
    func testConfigEnvironmentOverridesFile() throws {
        try withTemporaryPath { path in
            try KktConfig.save(KktConfig(userId: 12, lockPath: "/tmp/custom.lock", verifiedKakaoVersions: ["26.9"]), path: path)
            let config = try KktConfig.load(path: path, environment: ["KKT_USER_ID": "34"])
            XCTAssertEqual(config.userId, 34)
            XCTAssertEqual(config.lockPath, "/tmp/custom.lock")
            XCTAssertEqual(config.verifiedKakaoVersions, ["26.9"])
        }
    }

    func testConfigSavedWith0600() throws {
        try withTemporaryPath { path in
            try KktConfig.save(KktConfig(userId: 12), path: path)
            let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o600)
            XCTAssertEqual(try KktConfig.load(path: path, environment: [:]).userId, 12)
        }
    }

    func testDefaultLockPath() throws {
        try withTemporaryPath { path in
            let config = try KktConfig.load(path: path, environment: [:])
            XCTAssertEqual(config.lockPath, ("~/.config/kkt/kkt.lock" as NSString).expandingTildeInPath)
            XCTAssertNil(config.userId)
            XCTAssertEqual(config.verifiedKakaoVersions, [])
        }
    }

    func testPartialConfigUsesDefaults() throws {
        try withTemporaryPath { path in
            try Data(#"{"userId":12}"#.utf8).write(to: URL(fileURLWithPath: path))
            let config = try KktConfig.load(path: path, environment: [:])
            XCTAssertEqual(config.userId, 12)
            XCTAssertEqual(config.lockPath, KktConstants.lockPath)
            XCTAssertEqual(config.verifiedKakaoVersions, [])
        }
    }

    private func withTemporaryPath(_ body: (String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("config.json").path)
    }
}

final class DatabaseTests: XCTestCase {
    func testEncryptedDatabaseOpensCompatibilityFourAndThree() throws {
        let key = KeyDerivation.secureKey(userId: 12345, uuid: "00000000-1111-2222-3333-444444444444")
        for compatibility in [4, 3] {
            try withDatabase(key: key, compatibility: compatibility) { path in
                let database = try KakaoDatabase.open(databasePath: path, key: key)
                defer { database.close() }
                let values = try database.query("SELECT ?, ?, ?, ?, ?", bind: [
                    .int64(1234567890123456789), .string("한글\0본문"), .double(2.5), .null, .int(42),
                ]) { row in
                    XCTAssertEqual(row.int64(0), 1234567890123456789)
                    XCTAssertEqual(row.string(1), "한글\0본문")
                    XCTAssertEqual(row.double(2), 2.5)
                    XCTAssertNil(row.optionalInt64(3))
                    return row.int(4)
                }
                XCTAssertEqual(values, [42])
            }
        }
    }

    func testDatabaseRejectsWritesAndClosedQueries() throws {
        try withDatabase { path in
            let database = try KakaoDatabase.open(databasePath: path)
            XCTAssertThrowsError(try database.query("DELETE FROM sample", bind: []) { $0.int(0) }) {
                XCTAssertEqual($0 as? KktError, .readOnlySQL)
            }
            database.close()
            XCTAssertThrowsError(try database.query("SELECT 1", bind: []) { $0.int(0) }) {
                XCTAssertEqual($0 as? KktError, .databaseUnavailable)
            }
        }
    }

    func testDatabasePropagatesStepErrors() throws {
        try withDatabase { path in
            let database = try KakaoDatabase.open(databasePath: path)
            defer { database.close() }
            XCTAssertThrowsError(try database.query("SELECT abs(-9223372036854775808)", bind: []) { $0.int(0) }) {
                XCTAssertEqual($0 as? KktError, .databaseUnavailable)
            }
        }
    }

    private func withDatabase(
        key: String? = nil, compatibility: Int = 4, body: (String) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("fixture.db").path
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &handle), SQLITE_OK)
        let writer = try XCTUnwrap(handle)
        do {
            if let key {
                XCTAssertEqual(sqlite3_exec(writer, "PRAGMA cipher_default_compatibility = \(compatibility)", nil, nil, nil), SQLITE_OK)
                XCTAssertEqual(sqlite3_exec(writer, "PRAGMA KEY='\(key)'", nil, nil, nil), SQLITE_OK)
            }
            XCTAssertEqual(sqlite3_exec(writer, "CREATE TABLE sample (value TEXT)", nil, nil, nil), SQLITE_OK)
        }
        sqlite3_close(writer)
        try body(path)
    }
}

final class VersionTests: XCTestCase {
    private enum Fixture {
        static let changelogPath = "../../../CHANGELOG.md"
        static let releaseHeading = "## v"
        static let headingEnd = " "
    }

    func testVersionMatchesTheLatestReleaseInTheChangelog() throws {
        let changelog = URL(fileURLWithPath: #filePath).appendingPathComponent(Fixture.changelogPath).standardizedFileURL
        let lines = try String(contentsOf: changelog, encoding: .utf8).components(separatedBy: .newlines)
        let heading = try XCTUnwrap(lines.first { $0.hasPrefix(Fixture.releaseHeading) })
        let released = heading.dropFirst(Fixture.releaseHeading.count).prefix { String($0) != Fixture.headingEnd }

        XCTAssertEqual(KktConstants.version, String(released))
    }
}
