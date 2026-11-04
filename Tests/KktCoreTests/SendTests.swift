import AppKit
import ApplicationServices
import Foundation
@testable import KktCore
import XCTest

final class SendTests: XCTestCase {
    private enum Fixture {
        static let chatId: Int64 = 42
        static let me: Int64 = 7
        static let other: Int64 = 8
        static let start: Int64 = 100
        static let next: Int64 = 101
        static let old: Int64 = 90
        static let directType = 0
        static let groupType = 1
        static let openType = 4
        static let selfType = 5
        static let noLink: Int64 = 0
        static let linkId: Int64 = 99
        static let unique = 1
        static let duplicate = 2
        static let title = "모집방"
        static let link = "https://open.kakao.com/o/AbCdEf12"
        static let code = "AbCdEf12"
        static let text = "테스트 메시지 / 예시"
        static let spacedText = "  테스트\n메시지 /  예시\t"
        static let emptyText = ""
        static let lockedTexts = ["모집방", "대화할 때 주의가 필요한 방입니다.", "💳 현금영수증 / 지출증빙 안내"]
        static let poll = 0.5
        static let timeout = 10.0
        static let epoch = 0.0
        static let initialFetchCount = 0
        static let successfulFetchCount = 2
        static let differentText = "다른 본문"
        static let fakePid: pid_t = 123
        static let minimumInterval = 2.0
        static let lastSendSuffix = ".last-send"
        static let ambiguousCode = "ambiguous_name"
        static let sleepEvent = "sleep"
        static let sendEvent = "send"
    }

    private func room(type: Int, linkId: Int64 = Fixture.noLink, linkUrl: String? = nil) -> RoomRow {
        RoomRow(chatId: Fixture.chatId, type: type, linkId: linkId,
                linkUrl: linkUrl, displayName: Fixture.title)
    }

    func testResolveOpenLinkUsesCode() throws {
        let target = try resolveTarget(chatId: Fixture.chatId,
            room: room(type: Fixture.openType, linkId: Fixture.linkId, linkUrl: Fixture.link),
            sameNameCount: Fixture.duplicate)
        XCTAssertEqual(target, .openLink(code: Fixture.code, title: Fixture.title))
    }

    func testResolveTargetRejectsDuplicateNames() {
        XCTAssertThrowsError(try resolveTarget(chatId: Fixture.chatId,
            room: room(type: Fixture.directType), sameNameCount: Fixture.duplicate)) { error in
            XCTAssertEqual(error as? KktError, .ambiguous(Fixture.title))
        }
    }

    func testResolveSelfChat() throws {
        XCTAssertEqual(try resolveTarget(chatId: Fixture.chatId,
            room: room(type: Fixture.selfType), sameNameCount: Fixture.duplicate), .selfChat(name: Fixture.title))
    }

    func testResolveDirectAndGroupTargets() throws {
        XCTAssertEqual(try resolveTarget(chatId: Fixture.chatId,
            room: room(type: Fixture.directType), sameNameCount: Fixture.unique), .direct(name: Fixture.title))
        XCTAssertEqual(try resolveTarget(chatId: Fixture.chatId,
            room: room(type: Fixture.groupType), sameNameCount: Fixture.unique), .group(name: Fixture.title))
    }

    func testVerifyFindsNewMessage() {
        let rows = [SentRow(logId: Fixture.next, authorId: Fixture.me, message: Fixture.spacedText)]
        XCTAssertEqual(SendVerifier.match(rows: rows, myUserId: Fixture.me,
            startLogId: Fixture.start, text: Fixture.text), Fixture.next)
        XCTAssertEqual(SendVerifier.match(rows: rows, myUserId: Fixture.me,
            startLogId: Fixture.start, text: Fixture.spacedText), Fixture.next)
    }

    func testVerifyIgnoresOlderIdenticalMessage() {
        let rows = [SentRow(logId: Fixture.old, authorId: Fixture.me, message: Fixture.text)]
        XCTAssertNil(SendVerifier.match(rows: rows, myUserId: Fixture.me,
            startLogId: Fixture.start, text: Fixture.text))
    }

    func testVerifyIgnoresOthersMessage() {
        let rows = [SentRow(logId: Fixture.next, authorId: Fixture.other, message: Fixture.text)]
        XCTAssertNil(SendVerifier.match(rows: rows, myUserId: Fixture.me,
            startLogId: Fixture.start, text: Fixture.text))
    }

    func testVerifyTimesOutAsUncertain() throws {
        var now = Date(timeIntervalSince1970: Fixture.epoch)
        let result = try SendVerifier.await(poll: Fixture.poll, timeout: Fixture.timeout,
            myUserId: Fixture.me, startLogId: Fixture.start, text: Fixture.text,
            fetch: { [] }, sleep: { now.addTimeInterval($0) }, clock: { now })
        XCTAssertEqual(result, .uncertain)
        XCTAssertEqual(now.timeIntervalSince1970, Fixture.timeout)
    }

    func testVerifyWaitsForMatchingNewOwnMessage() throws {
        var now = Date(timeIntervalSince1970: Fixture.epoch)
        var fetchCount = Fixture.initialFetchCount
        let result = try SendVerifier.await(poll: Fixture.poll, timeout: Fixture.timeout,
            myUserId: Fixture.me, startLogId: Fixture.start, text: Fixture.text,
            fetch: {
                fetchCount += Fixture.unique
                let author = fetchCount == Fixture.successfulFetchCount ? Fixture.me : Fixture.other
                return [SentRow(logId: Fixture.next, authorId: author, message: Fixture.spacedText)]
            }, sleep: { now.addTimeInterval($0) }, clock: { now })
        XCTAssertEqual(result, .sent(logId: Fixture.next))
        XCTAssertEqual(fetchCount, Fixture.successfulFetchCount)
        XCTAssertEqual(now.timeIntervalSince1970, Fixture.poll)
    }

    func testVerifierRetriesTransientFetchErrors() throws {
        for recovers in [true, false] {
            var now = Date(timeIntervalSince1970: Fixture.epoch)
            var fetchCount = Fixture.initialFetchCount
            var sleeps: [TimeInterval] = []
            let result = try SendVerifier.await(poll: Fixture.poll, timeout: Fixture.timeout,
                myUserId: Fixture.me, startLogId: Fixture.start, text: Fixture.text,
                fetch: {
                    fetchCount += Fixture.unique
                    guard recovers && fetchCount == Fixture.successfulFetchCount else { throw KktError.busy }
                    return [SentRow(logId: Fixture.next, authorId: Fixture.me, message: Fixture.text)]
                }, sleep: { sleeps.append($0); now.addTimeInterval($0) }, clock: { now })
            XCTAssertEqual(result, recovers ? .sent(logId: Fixture.next) : .uncertain)
            XCTAssertEqual(now.timeIntervalSince1970, recovers ? Fixture.poll : Fixture.timeout)
            XCTAssertFalse(sleeps.isEmpty)
            XCTAssertTrue(sleeps.allSatisfy { $0 == Fixture.poll })
        }
    }

    func testVerifyRejectsDifferentTextAndStartBoundary() {
        let rows = [
            SentRow(logId: Fixture.start, authorId: Fixture.me, message: Fixture.text),
            SentRow(logId: Fixture.next, authorId: Fixture.me, message: Fixture.differentText),
        ]
        XCTAssertNil(SendVerifier.match(rows: rows, myUserId: Fixture.me,
            startLogId: Fixture.start, text: Fixture.text))
    }

    func testClassifyLockedInput() {
        XCTAssertEqual(classifyInput(windowTexts: Fixture.lockedTexts, hasField: false), .locked)
        XCTAssertEqual(classifyInput(windowTexts: Fixture.lockedTexts, hasField: true), .ready)
        XCTAssertEqual(classifyInput(windowTexts: [Fixture.title], hasField: false), .missing)
    }

    func testVerifyImagesOnlyAcceptsAnyOwnMessage() {
        let rows = [
            SentRow(logId: Fixture.old, authorId: Fixture.me, message: nil),
            SentRow(logId: Fixture.next, authorId: Fixture.other, message: Fixture.text),
            SentRow(logId: Fixture.next, authorId: Fixture.me, message: nil),
        ]
        XCTAssertEqual(SendVerifier.match(rows: rows, myUserId: Fixture.me,
            startLogId: Fixture.start, text: Fixture.emptyText), Fixture.next)
    }
}

final class SendQueryTests: XCTestCase {
    private enum Fixture {
        static let databaseExtension = ".db"
        static let sqlitePath = "/usr/bin/sqlite3"
        static let successStatus: Int32 = 0
        static let chatId: Int64 = 42
        static let missingChatId: Int64 = 999
        static let groupChatId: Int64 = 43
        static let friendChatId: Int64 = 44
        static let displayChatId: Int64 = 45
        static let nicknameChatId: Int64 = 46
        static let namedChatId: Int64 = 47
        static let selfChatId: Int64 = 48
        static let clearOwnNickname = "UPDATE NTUser SET nickName=NULL WHERE userId=7 AND linkId=0;"
        static let title = "모집방"
        static let duplicateName = "동명"
        static let displayName = "화면이름"
        static let nickname = "별명"
        static let explicitName = "지정이름"
        static let linkUrl = "https://open.kakao.com/o/AbCdEf12"
        static let duplicateCount = 2
        static let start: Int64 = 100
        static let next: Int64 = 101
        static let delayed: Int64 = 103
        static let insertDelayed = "INSERT INTO NTChatMessage VALUES (103,42,99,7,NULL);"
        static let schema = """
            CREATE TABLE NTChatRoom (chatId INTEGER, type INTEGER, linkId INTEGER,
                chatName TEXT, directChatMemberUserId INTEGER);
            CREATE TABLE NTOpenLink (linkId INTEGER, linkUrl TEXT, linkName TEXT);
            CREATE TABLE NTChatMeta (chatId INTEGER, type INTEGER, groupNickname TEXT);
            CREATE TABLE NTUser (userId INTEGER, linkId INTEGER,
                friendNickName TEXT, displayName TEXT, nickName TEXT);
            CREATE TABLE NTChatMessage (logId INTEGER, chatId INTEGER,
                type INTEGER, authorId INTEGER, message TEXT);
            CREATE TABLE NTChatContext (userId INTEGER);
            INSERT INTO NTChatContext VALUES (7);
            INSERT INTO NTChatRoom VALUES (42,4,99,'',0), (43,1,0,'',0),
                (44,0,0,NULL,11), (45,0,0,'',12), (46,0,0,'',13), (47,1,99,'지정이름',0),
                (48,5,0,'지정이름',8), (49,0,0,'',14);
            INSERT INTO NTOpenLink VALUES (99,'https://open.kakao.com/o/AbCdEf12','모집방');
            INSERT INTO NTChatMeta VALUES (43,3,'동명'), (47,3,'다른이름');
            INSERT INTO NTUser VALUES (11,0,'동명','다른이름','별명'),
                (11,99,'오픈닉네임',NULL,NULL), (12,0,NULL,'화면이름','별명'),
                (13,0,NULL,NULL,'별명'), (7,99,NULL,'오픈이름','오픈닉네임'),
                (8,0,NULL,'다른이름','다른별명'), (7,0,'친구이름','화면이름','별명'),
                (14,0,'','','판매자닉');
            INSERT INTO NTChatMessage VALUES (90,42,1,7,'old'), (100,42,1,7,'start'),
                (101,42,1,7,'new'), (102,43,1,7,'other room'),
                (9223372036854775807,42,99,7,'pending');
            """
    }

    private func write(_ sql: String, path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Fixture.sqlitePath)
        process.arguments = [path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, Fixture.successStatus)
    }

    private func withDatabase(_ body: (KakaoDatabase, String) throws -> Void) throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + Fixture.databaseExtension).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try write(Fixture.schema, path: path)
        let reader = try KakaoDatabase.open(databasePath: path)
        defer { reader.close() }
        try body(reader, path)
    }

    func testRoomDisplayNamesAndDuplicateCountUseTheSameExpression() throws {
        try withDatabase { reader, _ in
            let room = try XCTUnwrap(reader.room(chatId: Fixture.chatId))
            XCTAssertEqual(room.displayName, Fixture.title)
            XCTAssertEqual(room.linkUrl, Fixture.linkUrl)
            XCTAssertEqual(try reader.room(chatId: Fixture.groupChatId)?.displayName, Fixture.duplicateName)
            XCTAssertEqual(try reader.room(chatId: Fixture.friendChatId)?.displayName, Fixture.duplicateName)
            XCTAssertEqual(try reader.room(chatId: Fixture.displayChatId)?.displayName, Fixture.displayName)
            XCTAssertEqual(try reader.room(chatId: Fixture.nicknameChatId)?.displayName, Fixture.nickname)
            XCTAssertEqual(try reader.room(chatId: Fixture.namedChatId)?.displayName, Fixture.explicitName)
            XCTAssertEqual(try reader.sameNameCount(displayName: Fixture.duplicateName), Fixture.duplicateCount)
            XCTAssertNil(try reader.room(chatId: Fixture.missingChatId))
        }
    }

    func testEmptyStringNamesFallThroughToNickname() throws {
        try withDatabase { reader, _ in
            XCTAssertEqual(try reader.room(chatId: 49)?.displayName, "판매자닉")
            XCTAssertEqual(try reader.sameNameCount(displayName: "판매자닉"), 1)
        }
    }

    func testSentRowsExcludeOlderOtherRoomsAndPendingMessages() throws {
        try withDatabase { reader, _ in
            XCTAssertEqual(try reader.sentRows(chatId: Fixture.chatId, after: Fixture.start).map(\.logId),
                           [Fixture.next])
        }
    }

    func testSelfRoomUsesOwnNicknameFromUnlinkedUser() throws {
        try withDatabase { reader, _ in
            XCTAssertEqual(try reader.room(chatId: Fixture.selfChatId)?.displayName, Fixture.nickname)
        }
    }

    func testSelfRoomFallsBackToOwnDisplayName() throws {
        try withDatabase { reader, path in
            try write(Fixture.clearOwnNickname, path: path)
            XCTAssertEqual(try reader.room(chatId: Fixture.selfChatId)?.displayName, Fixture.displayName)
        }
    }

    func testSentRowsSeeNewWritesOnTheSameOpenConnection() throws {
        try withDatabase { reader, path in
            XCTAssertEqual(try reader.sentRows(chatId: Fixture.chatId, after: Fixture.start).map(\.logId),
                           [Fixture.next])
            try write(Fixture.insertDelayed, path: path)
            let rows = try reader.sentRows(chatId: Fixture.chatId, after: Fixture.start)
            XCTAssertEqual(rows.map(\.logId), [Fixture.next, Fixture.delayed])
            XCTAssertNil(rows.last?.message)
        }
    }

    func testRecentTextsReturnsLatestTypeOneMessagesWithLimit() throws {
        try withDatabase { reader, path in
            let expected = try reader.sentRows(chatId: Fixture.chatId, after: KktConstants.noLogId).compactMap(\.message)
            try write(Fixture.insertDelayed, path: path)
            XCTAssertEqual(try reader.recentTexts(chatId: Fixture.chatId, limit: KktConstants.cardIdentityTextLimit),
                           Array(expected.reversed()))
            XCTAssertEqual(try reader.recentTexts(chatId: Fixture.chatId, limit: KktConstants.one),
                           [try XCTUnwrap(expected.last)])
            XCTAssertTrue(try reader.recentTexts(chatId: Fixture.missingChatId, limit: KktConstants.cardIdentityTextLimit).isEmpty)
        }
    }

    func testRecentTextsPreservesEmptyAndShortRowsForIdentityRejection() throws {
        try withDatabase { reader, path in
            try write(KktConstants.SendTestSQL.identityRows, path: path)
            XCTAssertEqual(try reader.recentTexts(chatId: Fixture.chatId, limit: KktConstants.cardIdentityMinimumTextLength),
                           [KktConstants.SendTestSQL.shortText, KktConstants.emptyText])
        }
    }

    func testRecentTextsCapsHistoryAtRequestedLimit() throws {
        try withDatabase { reader, path in
            try write(KktConstants.SendTestSQL.manyRows, path: path)
            let texts = try reader.recentTexts(chatId: Fixture.chatId, limit: KktConstants.cardIdentityTextLimit)
            XCTAssertEqual(texts.count, KktConstants.cardIdentityTextLimit)
            XCTAssertTrue(texts.allSatisfy { $0 == Fixture.duplicateName })
        }
    }
}

private extension KktConstants {
    enum SendTestSQL {
        static let shortText = " 가 "
        static let identityRows = """
            INSERT INTO NTChatMessage VALUES (103,42,1,7,NULL), (104,42,1,7,'\(shortText)'),
                (105,42,99,7,'non-text');
            """
        static let manyRows = """
            WITH RECURSIVE history(logId) AS (
                SELECT 103 UNION ALL SELECT logId+1 FROM history WHERE logId<133
            ) INSERT INTO NTChatMessage SELECT logId,42,1,7,'동명' FROM history;
            """
    }
}

extension SendTests {
    private var cardRoute: CardRoute {
        CardRoute(roomChatId: Fixture.other, userId: Fixture.other, nickname: Fixture.differentText)
    }

    private final class CardUI {
        let window = AXUIElementCreateApplication(Fixture.fakePid)
        let table = AXUIElementCreateApplication(Fixture.fakePid + pid_t(Fixture.unique))
        let row = AXUIElementCreateApplication(Fixture.fakePid + pid_t(Fixture.duplicate))
        let text = AXUIElementCreateApplication(pid_t(Fixture.start))
        var cardCalls: [CardRoute] = []
        var sent = false
        var closed = false
        var inputChecked = false
        var recorded = false
        var waited = false
        var textRole = kAXStaticTextRole as String

        func dependencies(room: RoomRow) -> SendOperation.Dependencies {
            var dependencies = SendOperation.Dependencies()
            dependencies.room = { _ in room }
            dependencies.sameNameCount = { _ in Fixture.duplicate }
            dependencies.currentMaxLogId = { Fixture.start }
            dependencies.myUserId = { Fixture.me }
            dependencies.open = { _ in XCTFail(); return self.window }
            dependencies.openViaCard = { self.cardCalls.append($0); return self.window }
            dependencies.directChatId = { userId in
                XCTAssertEqual(userId, Fixture.other)
                return Fixture.chatId
            }
            dependencies.recentTexts = { chatId, limit in
                XCTAssertEqual(chatId, Fixture.chatId)
                XCTAssertEqual(limit, KktConstants.cardIdentityTextLimit)
                return [Fixture.text]
            }
            dependencies.title = { _ in room.displayName }
            dependencies.identifier = { CFEqual($0, self.table) ? KktConstants.DoctorAX.messageTable : nil }
            dependencies.children = { element in
                if CFEqual(element, self.window) { return [self.table] }
                if CFEqual(element, self.table) { return [self.row] }
                if CFEqual(element, self.row) { return [self.text] }
                return []
            }
            dependencies.role = { element in
                if CFEqual(element, self.table) { return kAXTableRole as String }
                if CFEqual(element, self.text) { return self.textRole }
                return kAXGroupRole as String
            }
            dependencies.value = { _ in Fixture.text }
            dependencies.close = { _ in self.closed = true }
            dependencies.isWindowOpen = { _ in !self.closed }
            dependencies.inputState = { _ in self.inputChecked = true; return .ready }
            dependencies.send = { _, text, images in
                XCTAssertTrue(self.waited)
                XCTAssertEqual(text, Fixture.text)
                XCTAssertTrue(images.isEmpty)
                self.sent = true
                return nil
            }
            dependencies.wait = { self.waited = true }
            dependencies.record = { self.recorded = true }
            dependencies.verify = { chatId, start, me, text, _ in
                XCTAssertTrue(self.recorded)
                XCTAssertEqual(chatId, Fixture.chatId)
                XCTAssertEqual(start, Fixture.start)
                XCTAssertEqual(me, Fixture.me)
                XCTAssertEqual(text, Fixture.text)
                return .sent(logId: Fixture.next)
            }
            return dependencies
        }
    }

    func testAmbiguousWithoutCardRoutePropagatesUnchanged() {
        let ui = CardUI()
        let dependencies = ui.dependencies(room: room(type: Fixture.directType))
        XCTAssertThrowsError(try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false)) {
            XCTAssertEqual($0 as? KktError, .ambiguous(Fixture.title))
        }
        XCTAssertTrue(ui.cardCalls.isEmpty)
        XCTAssertFalse(ui.sent)
    }

    func testAmbiguousDirectRoomUsesCardAndSends() throws {
        let ui = CardUI()
        let dependencies = ui.dependencies(room: room(type: Fixture.directType))
        let result = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)
        XCTAssertEqual(result, KktResult(result: KktConstants.sentResult, chatId: Fixture.chatId, logId: Fixture.next))
        XCTAssertEqual(ui.cardCalls, [cardRoute])
        XCTAssertTrue(ui.sent)
        XCTAssertTrue(ui.closed)
    }

    // KakaoTalk 26.9 exposes message bubble bodies as AXTextArea inside the message table (measured 2026-11-03).
    func testCardIdentityMatchesBubbleTextArea() throws {
        let ui = CardUI()
        ui.textRole = kAXTextAreaRole as String
        let dependencies = ui.dependencies(room: room(type: Fixture.directType))
        let result = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)
        XCTAssertEqual(result.result, KktConstants.sentResult)
        XCTAssertTrue(ui.sent)
    }

    func testSearchOpenerNotFoundOrAmbiguousUsesCard() throws {
        for error in [KktError.notFound(Fixture.title), .ambiguous(Fixture.title)] {
            let ui = CardUI()
            var dependencies = ui.dependencies(room: room(type: Fixture.directType))
            dependencies.sameNameCount = { _ in Fixture.unique }
            dependencies.open = { _ in throw error }
            let result = try SendOperation(dependencies: dependencies)
                .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)
            XCTAssertEqual(result.result, KktConstants.sentResult)
            XCTAssertEqual(ui.cardCalls, [cardRoute])
            XCTAssertTrue(ui.sent)
        }
    }

    func testMismatchedOrMissingDirectMemberRefusesCard() {
        for chatId in [Fixture.other, nil] {
            let ui = CardUI()
            var dependencies = ui.dependencies(room: room(type: Fixture.directType))
            dependencies.directChatId = { _ in chatId }
            XCTAssertThrowsError(try SendOperation(dependencies: dependencies)
                .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)) {
                XCTAssertEqual($0 as? KktError, .ambiguous(Fixture.title))
            }
            XCTAssertTrue(ui.cardCalls.isEmpty)
            XCTAssertFalse(ui.sent)
        }
    }

    func testCardIdentityMismatchClosesBeforeInput() {
        for titleMatches in [true, false] {
            let ui = CardUI()
            var dependencies = ui.dependencies(room: room(type: Fixture.directType))
            dependencies.title = { _ in titleMatches ? Fixture.title : Fixture.differentText }
            dependencies.value = { _ in titleMatches ? Fixture.differentText : Fixture.text }
            XCTAssertThrowsError(try SendOperation(dependencies: dependencies)
                .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)) {
                XCTAssertEqual($0 as? KktError, .ambiguous(Fixture.title))
            }
            XCTAssertEqual(ui.cardCalls, [cardRoute])
            XCTAssertTrue(ui.closed)
            XCTAssertFalse(ui.inputChecked)
            XCTAssertFalse(ui.sent)
        }
    }

    func testCardIdentityRequiresTextInsideMessageTable() {
        let ui = CardUI()
        var dependencies = ui.dependencies(room: room(type: Fixture.directType))
        dependencies.children = { CFEqual($0, ui.window) ? [ui.text] : [] }
        XCTAssertThrowsError(try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)) {
            XCTAssertEqual($0 as? KktError, .ambiguous(Fixture.title))
        }
        XCTAssertTrue(ui.closed)
        XCTAssertFalse(ui.sent)
    }

    func testCardIdentityRejectsMatchingTextInAnotherTable() {
        let ui = CardUI()
        var dependencies = ui.dependencies(room: room(type: Fixture.directType))
        dependencies.identifier = { _ in nil }
        XCTAssertThrowsError(try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)) {
            XCTAssertEqual($0 as? KktError, .ambiguous(Fixture.title))
        }
        XCTAssertTrue(ui.closed)
        XCTAssertFalse(ui.sent)
    }

    func testCardIdentityRejectsShortOrEmptyTextsEvenWhenTheyMatch() {
        for text in [String(Fixture.text.prefix(KktConstants.one)), KktConstants.emptyText, KktConstants.newline] {
            let ui = CardUI()
            var dependencies = ui.dependencies(room: room(type: Fixture.directType))
            dependencies.recentTexts = { _, _ in [text] }
            dependencies.value = { _ in text }
            XCTAssertThrowsError(try SendOperation(dependencies: dependencies)
                .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)) {
                XCTAssertEqual($0 as? KktError, .ambiguous(Fixture.title))
            }
            XCTAssertTrue(ui.closed)
            XCTAssertFalse(ui.inputChecked)
            XCTAssertFalse(ui.sent)
        }
    }

    func testCardIdentityTrimsDatabaseTextAndAcceptsAnyRecentMatch() throws {
        let ui = CardUI()
        var dependencies = ui.dependencies(room: room(type: Fixture.directType))
        dependencies.recentTexts = { _, _ in [Fixture.differentText, KktConstants.newline + Fixture.text + KktConstants.newline] }
        let result = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)
        XCTAssertEqual(result.result, KktConstants.sentResult)
        XCTAssertTrue(ui.sent)
    }

    func testCardIdentityWithoutDatabaseTextsUsesTitle() throws {
        let ui = CardUI()
        var dependencies = ui.dependencies(room: room(type: Fixture.directType))
        dependencies.recentTexts = { _, _ in [] }
        dependencies.children = { _ in [] }
        let result = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)
        XCTAssertEqual(result.result, KktConstants.sentResult)
        XCTAssertTrue(ui.sent)
    }

    func testGroupRoomNeverUsesCard() {
        let ui = CardUI()
        let dependencies = ui.dependencies(room: room(type: Fixture.groupType))
        XCTAssertThrowsError(try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)) {
            XCTAssertEqual($0 as? KktError, .ambiguous(Fixture.title))
        }
        XCTAssertTrue(ui.cardCalls.isEmpty)
        XCTAssertFalse(ui.sent)
    }

    func testCardPathFailureReasonPropagates() {
        for error in [KktError.automation(KktConstants.cardNotVisibleCode),
                      .automation(KktConstants.buttonNotFoundCode), .automation(KktConstants.contactWindowMissingCode),
                      .kakaoInUse, .chatWindowOpen] {
            let ui = CardUI()
            var dependencies = ui.dependencies(room: room(type: Fixture.directType))
            dependencies.openViaCard = { _ in throw error }
            XCTAssertThrowsError(try SendOperation(dependencies: dependencies)
                .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)) {
                XCTAssertEqual($0 as? KktError, error)
                XCTAssertEqual(ContactFlow.failureReason($0), ContactFlow.failureReason(error))
            }
            XCTAssertFalse(ui.sent)
        }
    }

    func testSuccessfulSearchDoesNotUseCardOrIdentityChecks() throws {
        let ui = CardUI()
        var dependencies = ui.dependencies(room: room(type: Fixture.directType))
        dependencies.sameNameCount = { _ in Fixture.unique }
        dependencies.open = { _ in ui.window }
        dependencies.directChatId = { _ in XCTFail(); return nil }
        dependencies.recentTexts = { _, _ in XCTFail(); return [] }
        let result = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)
        XCTAssertEqual(result.result, KktConstants.sentResult)
        XCTAssertTrue(ui.cardCalls.isEmpty)
        XCTAssertTrue(ui.sent)
    }

    func testOtherSearchErrorsDoNotUseCard() {
        let ui = CardUI()
        var dependencies = ui.dependencies(room: room(type: Fixture.directType))
        dependencies.sameNameCount = { _ in Fixture.unique }
        dependencies.open = { _ in throw KktError.chatWindowOpen }
        XCTAssertThrowsError(try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)) {
            XCTAssertEqual($0 as? KktError, .chatWindowOpen)
        }
        XCTAssertTrue(ui.cardCalls.isEmpty)
    }

    func testDatabaseNotFoundDoesNotTriggerCard() {
        let ui = CardUI()
        var dependencies = ui.dependencies(room: room(type: Fixture.directType))
        dependencies.sameNameCount = { _ in throw KktError.notFound(Fixture.title) }
        XCTAssertThrowsError(try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false, viaCard: cardRoute)) {
            XCTAssertEqual($0 as? KktError, .notFound(Fixture.title))
        }
        XCTAssertTrue(ui.cardCalls.isEmpty)
    }

    func testCardDryRunChecksIdentityWithoutSending() throws {
        let ui = CardUI()
        let dependencies = ui.dependencies(room: room(type: Fixture.directType))
        let result = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: true, viaCard: cardRoute)
        XCTAssertEqual(result, KktResult(result: KktConstants.dryRunResult, chatId: Fixture.chatId))
        XCTAssertEqual(ui.cardCalls, [cardRoute])
        XCTAssertTrue(ui.closed)
        XCTAssertFalse(ui.sent)
        XCTAssertFalse(ui.waited)
        XCTAssertFalse(ui.recorded)
    }

    func testMessageInputProceedsWhenKakaoTalkIsBackgroundBeforeImagePaste() throws {
        let window = AXUIElementCreateApplication(Fixture.fakePid)
        let scroll = AXUIElementCreateApplication(Fixture.fakePid + pid_t(KktConstants.singleUnit))
        let input = AXUIElementCreateApplication(Fixture.fakePid + pid_t(KktConstants.singleUnit + KktConstants.singleUnit))
        var frontmostBundleId: String?
        var events: [String] = []
        var dependencies = MessageInput.Dependencies()
        dependencies.frontmostBundleId = { frontmostBundleId }
        dependencies.children = { CFEqual($0, window) ? [scroll] : [input] }
        dependencies.role = { CFEqual($0, scroll) ? kAXScrollAreaRole as String : kAXTextAreaRole as String }
        dependencies.pasteImages = { _, _, _ in frontmostBundleId = KakaoApp.bundleId; return nil }
        dependencies.pid = { _ in Fixture.fakePid }
        dependencies.setText = { _, text in XCTAssertEqual(text, Fixture.text); return true }
        dependencies.pressReturn = { _ in events.append(Fixture.sendEvent) }
        try MessageInput(dependencies: dependencies).send(in: window, message: Fixture.text, images: [Fixture.text])
        XCTAssertEqual(events, [Fixture.sendEvent])
    }

    func testMessageInputRefusesWhileKakaoTalkIsFrontmost() {
        let element = AXUIElementCreateApplication(Fixture.fakePid)
        var dependencies = MessageInput.Dependencies()
        dependencies.frontmostBundleId = { KakaoApp.bundleId }
        dependencies.children = { _ in XCTFail(); return [] }
        dependencies.setText = { _, _ in XCTFail(); return false }
        dependencies.pressReturn = { _ in XCTFail() }
        dependencies.pasteImages = { _, _, _ in XCTFail(); return nil }
        XCTAssertThrowsError(try MessageInput(dependencies: dependencies)
            .send(in: element, message: Fixture.text, images: [Fixture.text])) {
            XCTAssertEqual($0 as? KktError, .kakaoInUse)
        }
    }

    func testSendRefusesAmbiguousRoomNames() throws {
        var calls = Fixture.initialFetchCount
        var dependencies = SendOperation.Dependencies()
        dependencies.room = { _ in self.room(type: Fixture.directType) }
        dependencies.sameNameCount = { _ in Fixture.duplicate }
        dependencies.open = { _ in calls += Fixture.unique; throw KktError.automation(Fixture.title) }
        let operation = SendOperation(dependencies: dependencies)
        XCTAssertThrowsError(try operation.execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false)) {
            XCTAssertEqual(($0 as? KktError)?.code, Fixture.ambiguousCode)
        }
        XCTAssertEqual(calls, Fixture.initialFetchCount)
    }

    func testSendWaitsMinimumInterval() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path + Fixture.lastSendSuffix) }
        var now = Date(timeIntervalSince1970: Fixture.epoch)
        var events: [String] = []
        let interval = SendInterval(path: path, clock: { now }, sleep: {
            events.append(Fixture.sleepEvent); now.addTimeInterval($0)
        })
        var dependencies = SendOperation.Dependencies()
        dependencies.room = { _ in self.room(type: Fixture.selfType) }
        dependencies.currentMaxLogId = { Fixture.start }
        dependencies.open = { _ in AXUIElementCreateApplication(Fixture.fakePid) }
        dependencies.close = { _ in }
        dependencies.inputState = { _ in .ready }
        dependencies.myUserId = { Fixture.me }
        dependencies.wait = { try interval.waitIfNeeded() }
        dependencies.record = { try interval.record() }
        dependencies.send = { _, _, _ in events.append(Fixture.sendEvent); return nil }
        dependencies.verify = { _, _, _, _, _ in .sent(logId: Fixture.next) }
        let operation = SendOperation(dependencies: dependencies)
        _ = try operation.execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false)
        _ = try operation.execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false)
        XCTAssertEqual(events, [Fixture.sendEvent, Fixture.sleepEvent, Fixture.sendEvent])
        XCTAssertEqual(now.timeIntervalSince1970, Fixture.minimumInterval)
    }
}

final class ImagePasteTests: XCTestCase {
    private enum Fixture {
        static let windowPid: pid_t = 101
        static let inputPid: pid_t = 102
        static let sheetPid: pid_t = 103
        static let buttonPid: pid_t = 104
        static let zero = 0
        static let one = 1
        static let image = "/tmp/image.png"
        static let singleTitle = "1개 전송"
        static let mismatchedTitle = "2개 전송"
        static let automationCode = "automation_failed"
        static let restore = "restore"
        static let activate = "activate"
        static let clipboard = "clipboard"
        static let paste = "paste"
        static let confirm = "confirm"
    }

    func testPasteRestoresFocusBeforeConfirmingExactFileCount() throws {
        let window = AXUIElementCreateApplication(Fixture.windowPid), input = AXUIElementCreateApplication(Fixture.inputPid)
        let sheet = AXUIElementCreateApplication(Fixture.sheetPid), button = AXUIElementCreateApplication(Fixture.buttonPid)
        var events: [String] = [], confirmed = false
        var dependencies = ImagePaste.Dependencies()
        dependencies.readClipboard = { [] }
        dependencies.restoreClipboard = { _ in }
        dependencies.captureFocus = { { events.append(Fixture.restore) } }
        dependencies.activate = { events.append(Fixture.activate) }
        dependencies.raise = { _ in }
        dependencies.click = { _ in }
        dependencies.writeFiles = { paths in XCTAssertEqual(paths, [Fixture.image]); events.append(Fixture.clipboard); return true }
        dependencies.paste = { events.append(Fixture.paste) }
        dependencies.sleep = { _ in }
        dependencies.children = { element in
            if CFEqual(element, window) { return confirmed ? [] : [sheet] }
            return CFEqual(element, sheet) ? [button] : []
        }
        dependencies.role = { CFEqual($0, sheet) ? kAXSheetRole as String : kAXButtonRole as String }
        dependencies.title = { _ in Fixture.singleTitle }
        dependencies.press = { _ in events.append(Fixture.confirm); confirmed = true; return true }
        try ImagePaste(dependencies: dependencies).send(in: window, input: input, images: [Fixture.image])
        XCTAssertEqual(events, [Fixture.activate, Fixture.clipboard, Fixture.paste, Fixture.restore, Fixture.confirm])
    }

    func testPasteRejectsMismatchedCountAndRestoresFocus() {
        let element = AXUIElementCreateApplication(Fixture.windowPid)
        var restored = false, pressed = false
        var dependencies = ImagePaste.Dependencies()
        dependencies.readClipboard = { [] }
        dependencies.restoreClipboard = { _ in }
        dependencies.captureFocus = { { restored = true } }
        dependencies.activate = {}
        dependencies.raise = { _ in }
        dependencies.click = { _ in }
        dependencies.writeFiles = { _ in true }
        dependencies.paste = {}
        dependencies.sleep = { _ in }
        dependencies.children = { _ in [element] }
        var roleCalls = Fixture.zero
        dependencies.role = { _ in roleCalls += Fixture.one; return roleCalls == Fixture.one ? kAXSheetRole as String : kAXButtonRole as String }
        dependencies.title = { _ in Fixture.mismatchedTitle }
        dependencies.press = { _ in pressed = true; return true }
        XCTAssertThrowsError(try ImagePaste(dependencies: dependencies).send(in: element, input: element, images: [Fixture.image])) {
            XCTAssertEqual(($0 as? KktError)?.code, Fixture.automationCode)
        }
        XCTAssertTrue(restored)
        XCTAssertFalse(pressed)
    }
}

final class ImageSendSafetyTests: XCTestCase {
    private enum Fixture {
        static let windowPid: pid_t = 301
        static let inputPid: pid_t = 302
        static let sheetPid: pid_t = 303
        static let sendPid: pid_t = 304
        static let cancelPid: pid_t = 305
        static let confirmPid: pid_t = 306
        static let textPid: pid_t = 307
        static let chatId: Int64 = 42
        static let me: Int64 = 7
        static let start: Int64 = 100
        static let next: Int64 = 101
        static let image = "/tmp/image.png"
        static let title = "나와의 채팅"
        static let sendTitle = "1개 전송"
        static let warning = "채팅방을 닫으시겠습니까? 채팅방을 닫으면 파일 다운로드와 업로드가 취소됩니다."
        static let cancel = "취소"
        static let confirm = "확인"
        static let photo = "사진"
        static let clipboardText = "original clipboard"
        static let customType = NSPasteboard.PasteboardType("test.kkt.binary")
        static let payload = Data([0, 1, 127, 255])
        static let epoch: TimeInterval = 0
        static let one = 1
        static let zero = 0
        static let imageVerifyTimeout: TimeInterval = 30
        static let slowSheet: TimeInterval = 3.6
        static let previewDelay: TimeInterval = 3
        static let tolerance = 0.00001
    }

    private final class UI {
        let window = AXUIElementCreateApplication(Fixture.windowPid)
        let input = AXUIElementCreateApplication(Fixture.inputPid)
        let sheet = AXUIElementCreateApplication(Fixture.sheetPid)
        let sendButton = AXUIElementCreateApplication(Fixture.sendPid)
        let cancelButton = AXUIElementCreateApplication(Fixture.cancelPid)
        let confirmButton = AXUIElementCreateApplication(Fixture.confirmPid)
        let warningText = AXUIElementCreateApplication(Fixture.textPid)
        var clipboardItems: ImagePaste.Clipboard = []
        var now = Date(timeIntervalSince1970: Fixture.epoch)
        var pastedAt: Date?
        var pressedAt: Date?
        var previewDelay = Fixture.epoch
        var sendDuration = Fixture.epoch
        var sendSleeps: [TimeInterval] = []
        var pressed: [AXUIElement] = []
        var closeCount = Fixture.zero
        var closeAt: Date?
        var warning = false
        var warningOnClose = false
        var warningDelay = Fixture.epoch
        var warningInText = false
        var clipboardAtPaste: [String] = []
        var clipboardAtSend: [[NSPasteboard.PasteboardType: Data]] = []

        func clipboard() -> [[NSPasteboard.PasteboardType: Data]] {
            clipboardItems
        }

        func seedClipboard() {
            clipboardItems = [[.string: Data(Fixture.clipboardText.utf8), Fixture.customType: Fixture.payload],
                              [.png: Fixture.payload]]
        }

        func children(_ element: AXUIElement) -> [AXUIElement] {
            if CFEqual(element, window) {
                if warningOnClose, let closeAt, now.timeIntervalSince(closeAt) >= warningDelay { warning = true }
                if warning { return [sheet] }
                guard let pastedAt, now.timeIntervalSince(pastedAt) >= previewDelay else { return [] }
                if let pressedAt, now.timeIntervalSince(pressedAt) >= sendDuration { return [] }
                return [sheet]
            }
            if CFEqual(element, sheet) {
                return warning ? [warningText, confirmButton, cancelButton] : [sendButton]
            }
            return []
        }

        func role(_ element: AXUIElement) -> String? {
            if CFEqual(element, sheet) { return kAXSheetRole as String }
            if CFEqual(element, warningText) { return kAXStaticTextRole as String }
            return kAXButtonRole as String
        }

        func title(_ element: AXUIElement) -> String? {
            if CFEqual(element, sheet) { return warning && !warningInText ? Fixture.warning : nil }
            if CFEqual(element, sendButton) { return Fixture.sendTitle }
            if CFEqual(element, cancelButton) { return Fixture.cancel }
            if CFEqual(element, confirmButton) { return Fixture.confirm }
            return nil
        }

        func sleep(_ interval: TimeInterval) {
            if pressedAt != nil { sendSleeps.append(interval) }
            now.addTimeInterval(interval)
        }

        var sendPressReportsFailure = false
        var sendPressIgnored = false

        func press(_ element: AXUIElement) -> Bool {
            pressed.append(element)
            if CFEqual(element, sendButton) {
                if sendPressIgnored { return false }
                clipboardAtSend = clipboard()
                pressedAt = now
                if sendPressReportsFailure { return false }
            }
            if CFEqual(element, cancelButton) { warning = false }
            return true
        }

        func imageDependencies() -> ImagePaste.Dependencies {
            var dependencies = ImagePaste.Dependencies()
            dependencies.captureFocus = { {} }
            dependencies.activate = {}
            dependencies.raise = { _ in }
            dependencies.click = { _ in }
            dependencies.readClipboard = { self.clipboardItems }
            dependencies.restoreClipboard = { self.clipboardItems = $0 }
            dependencies.writeFiles = { paths in
                self.clipboardItems = paths.map { [.fileURL: Data(URL(fileURLWithPath: $0).absoluteString.utf8)] }
                return true
            }
            dependencies.paste = {
                self.clipboardAtPaste = self.clipboardItems.compactMap { item in
                    item[.fileURL].flatMap { URL(string: String(decoding: $0, as: UTF8.self))?.path }
                }
                self.pastedAt = self.now
            }
            dependencies.children = children
            dependencies.role = role
            dependencies.title = title
            dependencies.press = press
            dependencies.sleep = sleep
            dependencies.clock = { self.now }
            return dependencies
        }

        func operationDependencies() -> SendOperation.Dependencies {
            var dependencies = SendOperation.Dependencies()
            dependencies.room = { _ in
                RoomRow(chatId: Fixture.chatId, type: KktConstants.selfRoomType,
                    linkId: KktConstants.noLinkId, linkUrl: nil, displayName: Fixture.title)
            }
            dependencies.currentMaxLogId = { Fixture.start }
            dependencies.myUserId = { Fixture.me }
            dependencies.open = { _ in self.window }
            dependencies.isWindowOpen = { _ in self.closeAt == nil || self.warningOnClose }
            dependencies.inputState = { _ in .ready }
            dependencies.send = { window, _, images in
                try ImagePaste(dependencies: self.imageDependencies()).send(in: window, input: self.input, images: images)
            }
            dependencies.close = { _ in
                self.closeCount += Fixture.one
                self.closeAt = self.now
                if self.warningOnClose && self.warningDelay == Fixture.epoch { self.warning = true }
            }
            dependencies.children = children
            dependencies.role = role
            dependencies.title = title
            dependencies.value = { CFEqual($0, self.warningText) && self.warning ? Fixture.warning : nil }
            dependencies.press = press
            dependencies.sleep = sleep
            dependencies.clock = { self.now }
            return dependencies
        }
    }

    func testClipboardRestoredAfterImageSend() throws {
        let ui = UI()
        ui.seedClipboard()
        let original = ui.clipboard()
        ui.previewDelay = Fixture.previewDelay
        try ImagePaste(dependencies: ui.imageDependencies()).send(in: ui.window, input: ui.input, images: [Fixture.image])
        XCTAssertEqual(ui.clipboardAtPaste, [Fixture.image])
        XCTAssertEqual(ui.clipboardAtSend, original)
        XCTAssertEqual(ui.clipboard(), original)
    }

    func testClipboardRestoredOnFailure() {
        let ui = UI()
        ui.seedClipboard()
        let original = ui.clipboard()
        var dependencies = ui.imageDependencies()
        dependencies.paste = { throw KktError.automation(KktConstants.automationCode) }
        XCTAssertThrowsError(try ImagePaste(dependencies: dependencies)
            .send(in: ui.window, input: ui.input, images: [Fixture.image]))
        XCTAssertEqual(ui.clipboard(), original)
    }

    func testSendPressReportingFailureStillSucceedsWhenSheetCloses() throws {
        let ui = UI()
        ui.sendDuration = 0
        ui.sendPressReportsFailure = true
        XCTAssertNoThrow(try ImagePaste(dependencies: ui.imageDependencies()).send(in: ui.window, input: ui.input, images: [Fixture.image]))
    }

    func testIgnoredSendPressFails() throws {
        let ui = UI()
        ui.sendPressIgnored = true
        XCTAssertThrowsError(try ImagePaste(dependencies: ui.imageDependencies()).send(in: ui.window, input: ui.input, images: [Fixture.image]))
    }

    func testWaitsForSendSheetToClose() throws {
        let ui = UI()
        ui.sendDuration = Fixture.slowSheet
        try ImagePaste(dependencies: ui.imageDependencies()).send(in: ui.window, input: ui.input, images: [Fixture.image])
        let pressedAt = try XCTUnwrap(ui.pressedAt)
        XCTAssertGreaterThanOrEqual(ui.now.timeIntervalSince(pressedAt), Fixture.slowSheet)
        XCTAssertFalse(ui.sendSleeps.isEmpty)
        XCTAssertTrue(ui.sendSleeps.allSatisfy { abs($0 - KktConstants.imageSheetPoll) < Fixture.tolerance })
    }

    func testPressedSendIsVerifiedByDatabase() throws {
        for rows in [[SentRow(logId: Fixture.next, authorId: Fixture.me, message: Fixture.photo)], []] {
            let ui = UI()
            ui.sendDuration = KktConstants.imageSheetTimeout + KktConstants.sendVerifyTimeout + KktConstants.imageSheetTimeout
            var dependencies = ui.operationDependencies()
            var verified = false
            dependencies.verify = { _, start, me, text, _ in
                verified = true
                XCTAssertNotNil(ui.pressedAt)
                XCTAssertEqual(ui.now.timeIntervalSince(try XCTUnwrap(ui.pressedAt)),
                    KktConstants.imageSheetTimeout, accuracy: Fixture.tolerance)
                return try SendVerifier.await(poll: KktConstants.sendVerifyPoll, timeout: KktConstants.sendVerifyTimeout,
                    myUserId: me, startLogId: start, text: text, fetch: { rows }, sleep: ui.sleep, clock: { ui.now })
            }
            let result = try SendOperation(dependencies: dependencies)
                .execute(chatId: Fixture.chatId, text: String(), images: [Fixture.image], dryRun: false)
            XCTAssertTrue(verified)
            XCTAssertEqual(result.result, KktConstants.uncertainResult)
            XCTAssertEqual(ui.closeCount, Fixture.zero)
        }
    }

    func testNeverConfirmsCancellingUpload() throws {
        for warningBeforeClose in [false, true] {
            for warningInText in [false, true] {
                let ui = UI()
                ui.warningInText = warningInText
                ui.warningOnClose = !warningBeforeClose
                var dependencies = ui.operationDependencies()
                dependencies.verify = { _, _, _, _, _ in
                    ui.warning = warningBeforeClose
                    return .sent(logId: Fixture.next)
                }
                let result = try SendOperation(dependencies: dependencies)
                    .execute(chatId: Fixture.chatId, text: String(), images: [Fixture.image], dryRun: false)
                XCTAssertEqual(result.result, KktConstants.uncertainResult)
                XCTAssertNil(result.logId)
                XCTAssertTrue(ui.pressed.contains { CFEqual($0, ui.cancelButton) })
                XCTAssertFalse(ui.pressed.contains { CFEqual($0, ui.confirmButton) })
                XCTAssertEqual(ui.closeCount, warningBeforeClose ? Fixture.zero : Fixture.one)
            }
        }
    }

    func testWaitsForSheetBeforeClosingOwnedWindow() throws {
        let ui = UI()
        ui.sendDuration = KktConstants.imageSheetTimeout + Fixture.slowSheet
        var dependencies = ui.operationDependencies()
        dependencies.verify = { _, _, _, _, _ in .sent(logId: Fixture.next) }
        let result = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: String(), images: [Fixture.image], dryRun: false)
        XCTAssertEqual(result.result, KktConstants.sentResult)
        XCTAssertEqual(ui.closeCount, Fixture.one)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ui.closeAt).timeIntervalSince(try XCTUnwrap(ui.pressedAt)), ui.sendDuration)
    }
}

extension ImageSendSafetyTests {
    func testSlowImageSheetPreservesDatabaseSentAndUncertainOutcomes() throws {
        for rows in [[SentRow(logId: Fixture.next, authorId: Fixture.me, message: Fixture.photo)], []] {
            let ui = UI()
            ui.sendDuration = KktConstants.imageSheetTimeout + Fixture.slowSheet
            var dependencies = ui.operationDependencies()
            dependencies.verify = { _, start, me, text, _ in
                try SendVerifier.await(poll: KktConstants.sendVerifyPoll, timeout: KktConstants.sendVerifyTimeout,
                    myUserId: me, startLogId: start, text: text, fetch: { rows }, sleep: ui.sleep, clock: { ui.now })
            }
            let result = try SendOperation(dependencies: dependencies)
                .execute(chatId: Fixture.chatId, text: String(), images: [Fixture.image], dryRun: false)
            XCTAssertEqual(result.result, rows.isEmpty ? KktConstants.uncertainResult : KktConstants.sentResult)
            XCTAssertEqual(result.logId, rows.first?.logId)
            XCTAssertEqual(ui.closeCount, Fixture.one)
        }
    }

    func testClipboardRestoredWhenFileWriteFails() {
        let ui = UI()
        ui.seedClipboard()
        let original = ui.clipboard()
        var dependencies = ui.imageDependencies()
        dependencies.writeFiles = { _ in ui.clipboardItems = []; return false }
        XCTAssertThrowsError(try ImagePaste(dependencies: dependencies)
            .send(in: ui.window, input: ui.input, images: [Fixture.image]))
        XCTAssertEqual(ui.clipboard(), original)
    }

    func testClipboardRestoredWhenSheetNeverAppears() {
        let ui = UI()
        ui.seedClipboard()
        let original = ui.clipboard()
        ui.previewDelay = KktConstants.imageSheetTimeout + Fixture.previewDelay
        XCTAssertThrowsError(try ImagePaste(dependencies: ui.imageDependencies())
            .send(in: ui.window, input: ui.input, images: [Fixture.image]))
        XCTAssertEqual(ui.clipboard(), original)
        XCTAssertNil(ui.pressedAt)
    }

    func testClipboardRestoredWhenSendButtonFails() {
        let ui = UI()
        ui.seedClipboard()
        let original = ui.clipboard()
        var dependencies = ui.imageDependencies()
        dependencies.press = { _ in false }
        XCTAssertThrowsError(try ImagePaste(dependencies: dependencies)
            .send(in: ui.window, input: ui.input, images: [Fixture.image]))
        XCTAssertEqual(ui.clipboard(), original)
    }

    func testPasteOnlyRestoresClipboardWithoutPressingSend() throws {
        let ui = UI()
        ui.seedClipboard()
        let original = ui.clipboard()
        try ImagePaste(dependencies: ui.imageDependencies())
            .send(in: ui.window, input: ui.input, images: [Fixture.image], pasteOnly: true)
        XCTAssertEqual(ui.clipboardAtPaste, [Fixture.image])
        XCTAssertEqual(ui.clipboard(), original)
        XCTAssertTrue(ui.pressed.isEmpty)
    }

    func testEmptyClipboardRestoredAfterImageSend() throws {
        let ui = UI()
        try ImagePaste(dependencies: ui.imageDependencies())
            .send(in: ui.window, input: ui.input, images: [Fixture.image])
        XCTAssertEqual(ui.clipboardAtPaste, [Fixture.image])
        XCTAssertTrue(ui.clipboard().isEmpty)
    }

    func testFailureCleanupNeverConfirmsCancellingUpload() throws {
        let ui = UI()
        ui.warningOnClose = true
        var dependencies = ui.operationDependencies()
        dependencies.send = { _, _, _ in throw KktError.automation(KktConstants.automationCode) }
        let result = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: String(), images: [Fixture.image], dryRun: false)
        XCTAssertEqual(result.result, KktConstants.uncertainResult)
        XCTAssertTrue(ui.pressed.contains { CFEqual($0, ui.cancelButton) })
        XCTAssertFalse(ui.pressed.contains { CFEqual($0, ui.confirmButton) })
        XCTAssertEqual(ui.closeCount, Fixture.one)
    }
}

extension ImageSendSafetyTests {
    func testDelayedCloseWarningIsCancelledAndReportedUncertain() throws {
        let ui = UI()
        ui.warningOnClose = true
        ui.warningDelay = Fixture.slowSheet
        var dependencies = ui.operationDependencies()
        dependencies.verify = { _, _, _, _, _ in .sent(logId: Fixture.next) }
        let result = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: String(), images: [Fixture.image], dryRun: false)
        XCTAssertEqual(result.result, KktConstants.uncertainResult)
        XCTAssertNil(result.logId)
        XCTAssertTrue(ui.pressed.contains { CFEqual($0, ui.cancelButton) })
        XCTAssertFalse(ui.pressed.contains { CFEqual($0, ui.confirmButton) })
        XCTAssertEqual(ui.closeCount, Fixture.one)
    }
}


extension ImageSendSafetyTests {
    func testRetriesCloseAfterUploadFinishes() throws {
        for uploadDuration in [Fixture.slowSheet, KktConstants.imageSheetTimeout + Fixture.slowSheet] {
            let ui = UI()
            var closed = false
            var closeTimes: [Date] = []
            var dependencies = ui.operationDependencies()
            dependencies.send = { _, _, _ in nil }
            dependencies.verify = { _, _, _, _, _ in .sent(logId: Fixture.next) }
            dependencies.children = { element in
                if CFEqual(element, ui.window) { return ui.warning ? [ui.sheet] : [] }
                if CFEqual(element, ui.sheet) { return [ui.warningText, ui.confirmButton, ui.cancelButton] }
                return []
            }
            dependencies.isWindowOpen = { _ in !closed }
            dependencies.close = { _ in
                closeTimes.append(ui.now)
                if ui.now.timeIntervalSince1970 < uploadDuration { ui.warning = true }
                else { closed = true }
            }
            let result = try SendOperation(dependencies: dependencies)
                .execute(chatId: Fixture.chatId, text: String(), images: [Fixture.image], dryRun: false)
            let finishes = uploadDuration < KktConstants.imageSheetTimeout
            XCTAssertEqual(result.result, finishes ? KktConstants.sentResult : KktConstants.uncertainResult)
            XCTAssertEqual(result.logId, finishes ? Fixture.next : nil)
            XCTAssertEqual(closed, finishes)
            XCTAssertGreaterThan(closeTimes.count, Fixture.one)
            if finishes {
                XCTAssertGreaterThanOrEqual(ui.now.timeIntervalSince1970, uploadDuration)
                XCTAssertLessThan(ui.now.timeIntervalSince1970, KktConstants.imageSheetTimeout)
            } else {
                XCTAssertEqual(ui.now.timeIntervalSince1970, KktConstants.imageSheetTimeout, accuracy: Fixture.tolerance)
            }
            for (previous, next) in zip(closeTimes, closeTimes.dropFirst()) {
                XCTAssertEqual(next.timeIntervalSince(previous), KktConstants.imageSheetPoll, accuracy: Fixture.tolerance)
            }
            XCTAssertTrue(ui.pressed.contains { CFEqual($0, ui.cancelButton) })
            XCTAssertFalse(ui.pressed.contains { CFEqual($0, ui.confirmButton) })
        }
    }

    func testImageSendUsesLongerVerifyTimeout() throws {
        for images in [[Fixture.image], []] {
            let ui = UI()
            var dependencies = ui.operationDependencies()
            dependencies.send = { _, _, _ in nil }
            var verified = false
            dependencies.verify = { _, start, me, text, timeout in
                verified = true
                XCTAssertEqual(timeout, images.isEmpty ? KktConstants.sendVerifyTimeout : Fixture.imageVerifyTimeout)
                return try SendVerifier.await(poll: KktConstants.sendVerifyPoll, timeout: timeout,
                    myUserId: me, startLogId: start, text: text,
                    fetch: {
                        guard ui.now.timeIntervalSince1970 >= KktConstants.sendVerifyTimeout + Fixture.slowSheet else {
                            return []
                        }
                        return [SentRow(logId: Fixture.next, authorId: me, message: Fixture.photo)]
                    }, sleep: ui.sleep, clock: { ui.now })
            }
            let result = try SendOperation(dependencies: dependencies)
                .execute(chatId: Fixture.chatId, text: String(), images: images, dryRun: false)
            XCTAssertTrue(verified)
            XCTAssertEqual(result.result, images.isEmpty ? KktConstants.uncertainResult : KktConstants.sentResult)
            XCTAssertEqual(result.logId, images.isEmpty ? nil : Fixture.next)
        }
    }
}
