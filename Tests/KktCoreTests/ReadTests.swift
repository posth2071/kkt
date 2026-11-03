import CSQLCipher
import Foundation
import XCTest
@testable import KktCore

final class ReadTests: XCTestCase {
    private enum Fixture {
        static let largeId: Int64 = 1_234_567_890_123_456_789
        static let logId: Int64 = 1_234_567_890_123_456_799
        static let now = Date(timeIntervalSince1970: 1_800_000_000)
        static let title = "방 제목"
        static let nickname = "단체 별명"
        static let openName = "오픈 이름"
        static let friend = "친구 이름"
        static let members = ["가", "나", "다", "라", "마"]
        static let schema = """
            CREATE TABLE NTChatRoom (chatId INTEGER, type INTEGER, chatName TEXT, linkId INTEGER,
                directChatMemberUserId INTEGER, activeMembersCount INTEGER, displayMemberIds BLOB,
                lastLogId INTEGER, lastUpdatedAt INTEGER, countOfNewMessage INTEGER);
            CREATE TABLE NTChatMeta (chatId INTEGER, type INTEGER, groupNickname TEXT);
            CREATE TABLE NTOpenLink (linkId INTEGER, linkName TEXT);
            CREATE TABLE NTUser (userId INTEGER, linkId INTEGER, friendNickName TEXT, displayName TEXT, nickName TEXT);
            CREATE TABLE NTChatContext (userId INTEGER);
            CREATE TABLE NTChatMessage (logId INTEGER, chatId INTEGER, authorId INTEGER,
                message TEXT, type INTEGER, sentAt INTEGER);
            INSERT INTO NTChatContext VALUES (1);
            INSERT INTO NTOpenLink VALUES (7, '오픈 이름');
            INSERT INTO NTUser VALUES (2, 0, '친구 이름', '표시 이름', '닉네임');
            INSERT INTO NTUser VALUES (2, 7, '', '', '오픈 별명');
            INSERT INTO NTChatRoom VALUES (1, 1, '방 제목', 7, 2, 2, NULL, 0, 10, 3);
            INSERT INTO NTChatRoom VALUES (2, 1, '', 7, 2, 2, NULL, 0, 9, 0);
            INSERT INTO NTChatMeta VALUES (1, 3, '단체 별명'), (2, 3, '단체 별명');
            INSERT INTO NTChatRoom VALUES (3, 4, '', 7, 2, 2, NULL, 0, 8, 0);
            INSERT INTO NTChatMeta VALUES (3, 3, '');
            INSERT INTO NTChatRoom VALUES (4, 0, '', 0, 2, 2, NULL, 0, 7, 0);
            INSERT INTO NTChatRoom VALUES (5, 1, '', 0, 0, 8, NULL, 0, 6, 0);
            INSERT INTO NTChatRoom VALUES (6, 1, '중복 방 A', 0, 0, 2, NULL, 0, 5, 0);
            INSERT INTO NTChatRoom VALUES (7, 1, '중복 방 B', 0, 0, 2, NULL, 0, 4, 0);
            INSERT INTO NTChatRoom VALUES (1234567890123456789, 4, '큰 방', 7, 0, 2, NULL,
                1234567890123456799, 1800000000, 0);
            INSERT INTO NTChatMessage VALUES (1234567890123456799, 1234567890123456789, 2, '검색어500', 1, 1800000000);
            INSERT INTO NTChatMessage VALUES (10, 1, 1, '검색어500 과거', 1, 1700000000);
            INSERT INTO NTChatMessage VALUES (11, 1, 1, '다른 본문', 1, 1800000000);
            """
    }

    func testDisplayNamePriority() throws {
        try withDatabase { database, writer in
            let plist = try PropertyListSerialization.data(fromPropertyList: [11, 12, 13, 14, 15],
                                                           format: .binary, options: 0)
            let hex = plist.map { String(format: "%02x", $0) }.joined()
            try execute(writer, "UPDATE NTChatRoom SET displayMemberIds=X'\(hex)' WHERE chatId=5")
            for (offset, name) in Fixture.members.enumerated() {
                try execute(writer, "INSERT INTO NTUser VALUES (\(offset + 11), 0, '', '\(name)', '')")
                try execute(writer, "INSERT INTO NTUser VALUES (\(offset + 11), 9, '잘못된 이름', '', '')")
            }
            let rooms = try ReadQueries(database: database).chats(limit: 50)
            let names = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0.displayName) })
            XCTAssertEqual(names[1], Fixture.title)
            XCTAssertEqual(names[2], Fixture.nickname)
            XCTAssertEqual(names[3], Fixture.openName)
            XCTAssertEqual(names[4], Fixture.friend)
            XCTAssertEqual(names[5], "가, 나, 다, 라 외 3명")
            XCTAssertTrue(RoomNames.displayNameExpression.contains("r.chatName"))
            XCTAssertEqual(RoomNames.memberName(hex: "invalid", memberCount: 8, users: [:]), nil)
        }
    }

    func testChatNameResolvesUniqueOrListsCandidates() throws {
        try withDatabase { database, _ in
            let reader = ReadQueries(database: database)
            let unique = try reader.resolveChat(named: "중복 방 A")
            XCTAssertEqual(unique.chatId, 6)
            XCTAssertEqual(unique.exitCode, 0)
            let ambiguous = try reader.resolveChat(named: "중복 방")
            XCTAssertNil(ambiguous.chatId)
            XCTAssertEqual(ambiguous.exitCode, 2)
            XCTAssertEqual(ambiguous.candidates.map(\.id), [6, 7])
            let output = TableOutput.candidates(ambiguous.candidates)
            XCTAssertTrue(output.contains("6"))
            XCTAssertTrue(output.contains("중복 방 A"))
            XCTAssertTrue(output.contains("7"))
            XCTAssertTrue(output.contains("중복 방 B"))
            XCTAssertEqual(try reader.resolveChat(named: "없는 방").exitCode, 2)
        }
    }

    func testSinceParses() {
        XCTAssertEqual(ReadQueries.parseSince("7d", now: Fixture.now), Fixture.now.addingTimeInterval(-604_800))
        XCTAssertEqual(ReadQueries.parseSince("12h", now: Fixture.now), Fixture.now.addingTimeInterval(-43_200))
        XCTAssertEqual(ReadQueries.parseSince("30m", now: Fixture.now), Fixture.now.addingTimeInterval(-1_800))
        for invalid in ["", "7", "bad", "-1h", "NaNd", "infd"] {
            XCTAssertNil(ReadQueries.parseSince(invalid, now: Fixture.now))
        }
    }

    func testMessagesAcceptsInt64ChatId() throws {
        try withDatabase { database, _ in
            let messages = try ReadQueries(database: database).messages(chatId: Fixture.largeId)
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages.first?.chatId, Fixture.largeId)
            XCTAssertEqual(messages.first?.id, Fixture.logId)
            XCTAssertEqual(messages.first?.sender, "오픈 별명")
            let json = KktOutput.line(messages)
            XCTAssertTrue(json.hasPrefix("["))
            XCTAssertTrue(json.contains("\"chat_id\":1234567890123456789"))
            XCTAssertTrue(json.contains("\"id\":1234567890123456799"))
            XCTAssertFalse(json.contains("\"1234567890123456789\""))
            let raw = try ReadQueries(database: database).query("SELECT chatId, lastLogId FROM NTChatRoom WHERE chatId=1234567890123456789")
            XCTAssertEqual(KktOutput.line(raw.rows), "[[1234567890123456789,1234567890123456799]]")
        }
    }

    func testReadCommandRetriesBusyDatabase() throws {
        var attempts = 0
        var sleeps: [TimeInterval] = []
        let result: [Int] = try ReadQueries.retry(sleep: { sleeps.append($0) }) {
            attempts += 1
            if attempts <= 2 { throw KktError.busy }
            return [42]
        }
        XCTAssertEqual(result, [42])
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(sleeps.count, 2)
        attempts = 0
        XCTAssertThrowsError(try ReadQueries.retry(sleep: { _ in }) { () -> [Int] in
            attempts += 1
            throw KktError.busy
        }) { XCTAssertEqual($0 as? KktError, .databaseUnavailable) }
        XCTAssertEqual(attempts, 3)
    }

    func testReadRetriesBusyDuringPrepare() throws {
        try withDatabase { database, writer in
            try execute(writer, "BEGIN EXCLUSIVE")
            defer { sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) }
            var waits = 0
            let rooms = try ReadQueries.retry(sleep: { _ in
                waits += 1
                try? self.execute(writer, "ROLLBACK")
            }) { try ReadQueries(database: database).chats() }
            XCTAssertEqual(waits, 1)
            XCTAssertEqual(rooms.count, 8)
        }
    }

    func testSearchAppliesRoomAndSinceFilters() throws {
        try withDatabase { database, _ in
            let reader = ReadQueries(database: database)
            XCTAssertEqual(try reader.search(text: "검색어500").count, 2)
            XCTAssertEqual(try reader.search(text: "검색어500", chatId: Fixture.largeId).map(\.id), [Fixture.logId])
            XCTAssertEqual(try reader.search(text: "검색어500", since: Fixture.now).map(\.id), [Fixture.logId])
            XCTAssertEqual(try reader.search(text: "검색어500", chatId: 1, since: Fixture.now).count, 0)
            XCTAssertEqual(try reader.messages(chatId: 1, limit: 1).map(\.id), [11])
        }
    }

    func testTableOutputAlignsKoreanAndKeepsOneLinePerRow() {
        let table = TableOutput.render(columns: ["이름", "ID"], rows: [["가", "1"], ["AB", "2"], ["줄\n바꿈", "3"]])
        let lines = table.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[1], "가        1")
        XCTAssertEqual(lines[2], "AB        2")
        XCTAssertFalse(lines[3].contains("\r"))
    }

    func testHumanOutputUsesLocalTime() throws {
        try withDatabase { database, _ in
            let reader = ReadQueries(database: database)
            let chats = try reader.chats()
            let messages = try reader.messages(chatId: Fixture.largeId)
            let search = try reader.search(text: "검색어500", chatId: Fixture.largeId)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            let expected = formatter.string(from: Fixture.now)
            XCTAssertTrue(TableOutput.chats(chats).contains(expected))
            XCTAssertTrue(TableOutput.messages(messages).contains(expected))
            XCTAssertTrue(TableOutput.messages(search).contains(expected))
            let seoul = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
            formatter.timeZone = seoul
            let seoulTime = formatter.string(from: Fixture.now)
            XCTAssertTrue(TableOutput.chats(chats, timeZone: seoul).contains(seoulTime))
            XCTAssertTrue(TableOutput.messages(messages, timeZone: seoul).contains(seoulTime))
            let iso = ISO8601DateFormatter().string(from: Fixture.now)
            XCTAssertFalse(TableOutput.chats(chats).contains(iso))
            XCTAssertFalse(TableOutput.messages(messages).contains(iso))
            XCTAssertTrue(KktOutput.line(chats).contains(iso))
            XCTAssertTrue(KktOutput.line(messages).contains(iso))
            XCTAssertTrue(KktOutput.line(search).contains(iso))
        }
    }

    private func withDatabase(_ body: (KakaoDatabase, OpaquePointer) throws -> Void) throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &handle), SQLITE_OK)
        let writer = try XCTUnwrap(handle)
        defer {
            sqlite3_close(writer)
            try? FileManager.default.removeItem(atPath: path)
        }
        try execute(writer, Fixture.schema)
        let database = try KakaoDatabase.open(databasePath: path)
        defer { database.close() }
        try body(database, writer)
    }

    private func execute(_ handle: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            XCTFail(String(cString: sqlite3_errmsg(handle)))
            throw KktError.databaseUnavailable
        }
    }
}
