import Foundation
import KktCore
import XCTest

final class ServeQueryTests: XCTestCase {
    private static let pendingLogId = "9223372036854775807"
    private enum ScrapFixture {
        static let chatId: Int64 = 7
        static let otherChatId: Int64 = 8
        static let logId: Int64 = 10
        static let nullLogId: Int64 = 11
        static let missingLogId: Int64 = 99
        static let preview = #"{"universalScrapData":{"title":"Example"},"urls":["https://example.com"]}"#
        static let sqlitePath = "/usr/bin/sqlite3"
        static let update = """
            UPDATE NTChatMessage SET attachment='\(preview)' WHERE chatId=7 AND logId=10;
            INSERT INTO NTChatMessage VALUES (10, 8, 1, 2, 'other', '{"urls":[]}', 1793619914);
            """
        static let otherAttachment = #"{"urls":[]}"#
    }

    private func makeDatabase() throws -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db").path
        let schema = """
            CREATE TABLE NTChatMessage (logId INTEGER, chatId INTEGER, type INTEGER, authorId INTEGER,
                message TEXT, attachment TEXT, sentAt INTEGER);
            CREATE TABLE NTChatRoom (chatId INTEGER, linkId INTEGER, type INTEGER, chatName TEXT,
                directChatMemberUserId INTEGER);
            CREATE TABLE NTChatMeta (chatId INTEGER, type INTEGER, groupNickname TEXT);
            CREATE TABLE NTOpenLink (linkId INTEGER, linkName TEXT);
            INSERT INTO NTOpenLink VALUES (100000001, '모집방');
            INSERT INTO NTChatRoom VALUES (8, 100000001, 4, '', 0);
            INSERT INTO NTChatMessage VALUES (12, 8, 1, 2, 'c', NULL, 1793619916);
            CREATE TABLE NTUser (userId INTEGER, linkId INTEGER, nickName TEXT, friendNickName TEXT, displayName TEXT);
            INSERT INTO NTChatRoom VALUES (7, 0, 0, '', 0);
            INSERT INTO NTChatMessage VALUES (10, 7, 1, 1, 'a', NULL, 1793619914);
            INSERT INTO NTChatMessage VALUES (11, 7, 1, 1, 'b', NULL, 1793619915);
            INSERT INTO NTChatMessage VALUES (\(Self.pendingLogId), 7, 2, 1, 'pending', NULL, 1786496877.86);
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, schema]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return path
    }

    func testMaxLogIdIgnoresPendingSentinel() throws {
        let reader = try KakaoDatabase.open(databasePath: try makeDatabase())
        defer { reader.close() }
        XCTAssertEqual(try reader.currentMaxLogId(), 12)
    }

    func testEventsAfterSkipsPendingSentinel() throws {
        let reader = try KakaoDatabase.open(databasePath: try makeDatabase())
        defer { reader.close() }
        let events = try reader.eventsAfter(logId: 10, limit: 500, myUserId: 1)
        XCTAssertEqual(events.map(\.logId), [11, 12])
        XCTAssertEqual(events.first?.isFromMe, true)
    }

    func testOpenChatNameComesFromOpenLink() throws {
        let reader = try KakaoDatabase.open(databasePath: try makeDatabase())
        defer { reader.close() }
        let events = try reader.eventsAfter(logId: 11, limit: 500, myUserId: 1)
        XCTAssertEqual(events.first?.chatName, "모집방")
        XCTAssertEqual(events.first?.linkId, 100000001)
    }

    func testScrapAttachmentReadsUpdatedRowByChatAndLogId() throws {
        let path = try makeDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try KakaoDatabase.open(databasePath: path)
        defer { reader.close() }
        XCTAssertNil(try reader.scrapAttachment(chatId: ScrapFixture.chatId, logId: ScrapFixture.logId))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ScrapFixture.sqlitePath)
        process.arguments = [path, ScrapFixture.update]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, KktConstants.successExitCode)
        XCTAssertEqual(
            try reader.scrapAttachment(chatId: ScrapFixture.chatId, logId: ScrapFixture.logId),
            ScrapFixture.preview
        )
        XCTAssertEqual(
            try reader.scrapAttachment(chatId: ScrapFixture.otherChatId, logId: ScrapFixture.logId),
            ScrapFixture.otherAttachment
        )
        XCTAssertNil(try reader.scrapAttachment(chatId: ScrapFixture.chatId, logId: ScrapFixture.nullLogId))
        XCTAssertNil(try reader.scrapAttachment(chatId: ScrapFixture.chatId, logId: ScrapFixture.missingLogId))
    }

    func testScrapAttachmentThrowsOnClosedReader() throws {
        let path = try makeDatabase()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try KakaoDatabase.open(databasePath: path)
        reader.close()
        XCTAssertThrowsError(try reader.scrapAttachment(chatId: ScrapFixture.chatId, logId: ScrapFixture.logId))
    }
}
