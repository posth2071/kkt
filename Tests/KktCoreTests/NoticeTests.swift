import ApplicationServices
import CSQLCipher
import Foundation
import XCTest
@testable import KktCore

final class NoticeTests: XCTestCase {
    private enum Fixture {
        static let chatId: Int64 = 18_000_000_000_000_001
        static let updatedAt: Int64 = 1_800_000_000
        static let shortText = String(repeating: "공", count: 489)
        static let boundaryText = String(repeating: "공", count: 490)
        static let preview = String(repeating: "공", count: 500)
        static let fullText = String(repeating: "공지 전문\n", count: 200)
        static var target: SendTarget { .group(name: "미션방") }
    }

    func testDatabaseNoticePreferred() throws {
        var uiCalls = Int.zero
        let reader = NoticeReader(fetch: { chatId in
            XCTAssertEqual(chatId, Fixture.chatId)
            return self.notice(Fixture.shortText)
        }, screen: { _ in uiCalls += 1; return Fixture.fullText })
        let result = try reader.read(chatId: Fixture.chatId)
        XCTAssertEqual(result.text, Fixture.shortText)
        XCTAssertEqual(result.source, "database")
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.updatedAt, Fixture.updatedAt)
        XCTAssertEqual(uiCalls, 0)
    }

    func testFallsBackToScreenWhenDatabaseTruncated() throws {
        for text in [Fixture.boundaryText, Fixture.preview] {
            let effects = ScreenEffects()
            let reader = NoticeReader(fetch: { _ in self.notice(text) }, screen: { chatId in
                XCTAssertEqual(chatId, Fixture.chatId)
                return try NoticeAX(dependencies: effects.dependencies()).read(Fixture.target)
            })
            let result = try reader.read(chatId: Fixture.chatId)
            XCTAssertEqual(result.text, Fixture.fullText)
            XCTAssertEqual(result.source, "screen")
            XCTAssertFalse(result.truncated)
            XCTAssertEqual(result.updatedAt, Fixture.updatedAt)
            XCTAssertEqual(effects.clicks, [CGPoint(x: 140, y: 215)])
            XCTAssertEqual(effects.events, ["open", "capture(cursor)", "raise", "activate", "click",
                                           "restore", "close(board)", "close(room)"])
            XCTAssertEqual(result.exitCode, 0)
        }
    }

    func testCrlfPreviewCountsUtf16Units() throws {
        let crlfPreview = String(repeating: "가\r\n", count: 167)
        XCTAssertLessThan(crlfPreview.count, KktConstants.Notice.truncationThreshold)
        let reader = NoticeReader(fetch: { _ in self.notice(crlfPreview) }, screen: { _ in throw KktError.chatWindowOpen })
        let result = try reader.read(chatId: Fixture.chatId)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.source, "truncated")
    }

    func testTruncatedWhenScreenUnavailable() throws {
        let effects = ScreenEffects()
        var dependencies = effects.dependencies()
        dependencies.open = { _ in throw KktError.chatWindowOpen }
        let reader = NoticeReader(fetch: { _ in self.notice(Fixture.preview) }, screen: { _ in
            try NoticeAX(dependencies: dependencies).read(Fixture.target)
        })
        let result = try reader.read(chatId: Fixture.chatId)
        XCTAssertEqual(result.source, "truncated")
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.text, Fixture.preview)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(effects.events.isEmpty)
        XCTAssertTrue(effects.clicks.isEmpty)
    }

    func testDatabaseReadsLatestType24NoticeForRoom() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &writer), SQLITE_OK)
        let handle = try XCTUnwrap(writer)
        defer {
            sqlite3_close(handle)
            try? FileManager.default.removeItem(atPath: path)
        }
        let schema = """
            CREATE TABLE NTChatMessage (logId INTEGER, chatId INTEGER, type INTEGER, attachment TEXT, sentAt INTEGER);
            INSERT INTO NTChatMessage VALUES
                (1, 18000000000000001, 24, '{"os":[{"t":1,"ct":"과거 공지"}]}', 1700000000),
                (2, 18000000000000001, 24, '{"os":[{"t":2,"ct":"다른 종류"},{"t":1,"ct":"최신 공지"}]}', 1800000000),
                (3, 18000000000000001, 24, '{"os":[{"t":2,"ct":"공지 아님"}]}', 1800000001),
                (4, 18000000000000001, 1, '{"os":[{"t":1,"ct":"메시지"}]}', 1800000002),
                (5, 7, 24, '{"os":[{"t":1,"ct":"다른 방"}]}', 1800000003),
                (6, 18000000000000001, 24, 'malformed', 1800000004);
            """
        XCTAssertEqual(sqlite3_exec(handle, schema, nil, nil, nil), SQLITE_OK)
        let database = try KakaoDatabase.open(databasePath: path)
        defer { database.close() }
        let result = try XCTUnwrap(NoticeReader.databaseNotice(database: database, chatId: Fixture.chatId))
        XCTAssertEqual(result.chatId, Fixture.chatId)
        XCTAssertEqual(result.text, "최신 공지")
        XCTAssertEqual(result.updatedAt, Fixture.updatedAt)
        XCTAssertEqual(result.source, "database")
        XCTAssertFalse(result.truncated)
        XCTAssertNil(try NoticeReader.databaseNotice(database: database, chatId: 8))
    }

    func testDatabaseFindsDeletedNoticeAsLatest() throws {
        let database = try noticeDatabase(rows: """
            (1, 18000000000000001, 24, '{"os":[{"t":1,"ct":"과거 공지"}]}', 1700000000),
            (2, 18000000000000001, 16408, '{"os":[{"t":1,"ct":"삭제 표시 공지"}]}', 1800000000),
            (3, 18000000000000001, 16385, '{"os":[{"t":1,"ct":"삭제된 글"}]}', 1800000001)
            """)
        defer { database.close() }
        let result = try XCTUnwrap(NoticeReader.databaseNotice(database: database, chatId: Fixture.chatId))
        XCTAssertEqual(result.text, "삭제 표시 공지")
        XCTAssertEqual(result.updatedAt, Fixture.updatedAt)
        XCTAssertTrue(result.messageDeleted)
    }

    func testDatabasePlainNoticeIsNotDeleted() throws {
        let database = try noticeDatabase(rows: """
            (1, 18000000000000001, 16408, '{"os":[{"t":1,"ct":"삭제 표시 공지"}]}', 1700000000),
            (2, 18000000000000001, 24, '{"os":[{"t":1,"ct":"최신 공지"}]}', 1800000000)
            """)
        defer { database.close() }
        let result = try XCTUnwrap(NoticeReader.databaseNotice(database: database, chatId: Fixture.chatId))
        XCTAssertEqual(result.text, "최신 공지")
        XCTAssertFalse(result.messageDeleted)
    }

    func testDeletedShortNoticeIsCheckedOnScreen() throws {
        let reader = NoticeReader(fetch: { _ in self.notice(Fixture.shortText, deleted: true) },
                                  screen: { _ in Fixture.fullText })
        let result = try reader.read(chatId: Fixture.chatId)
        XCTAssertEqual(result.text, Fixture.fullText)
        XCTAssertEqual(result.source, "screen")
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.updatedAt, Fixture.updatedAt)
    }

    func testDeletedNoticeIsMarkedUnverifiedWhenScreenFails() throws {
        let screens: [(Int64) throws -> String?] = [{ _ in nil }, { _ in throw KktError.chatWindowOpen }]
        for screen in screens {
            let reader = NoticeReader(fetch: { _ in self.notice(Fixture.shortText, deleted: true) }, screen: screen)
            let result = try reader.read(chatId: Fixture.chatId)
            XCTAssertEqual(result.text, Fixture.shortText)
            XCTAssertEqual(result.source, "truncated")
            XCTAssertTrue(result.truncated)
        }
    }

    func testDeletedFlagStaysOutOfOutput() throws {
        let line = KktOutput.line(notice(Fixture.shortText, deleted: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["chatId", "text", "source", "truncated", "updatedAt"])
    }

    func testDatabaseErrorsDoNotOpenScreen() {
        let reader = NoticeReader(fetch: { _ in throw KktError.databaseUnavailable },
                                  screen: { _ in XCTFail("No UI for failed DB reads"); return nil })
        XCTAssertThrowsError(try reader.read(chatId: Fixture.chatId)) {
            XCTAssertEqual($0 as? KktError, .databaseUnavailable)
        }
    }

    func testMissingRowReadsScreenThenRefetchesUpdatedAt() throws {
        var fetches = Int.zero
        let reader = NoticeReader(fetch: { _ in
            fetches += 1
            return fetches == 1 ? nil : self.notice(Fixture.preview)
        }, screen: { chatId in
            XCTAssertEqual(chatId, Fixture.chatId)
            return Fixture.fullText
        })
        let result = try reader.read(chatId: Fixture.chatId)
        XCTAssertEqual(result.text, Fixture.fullText)
        XCTAssertEqual(result.source, "screen")
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.updatedAt, Fixture.updatedAt)
        XCTAssertEqual(fetches, 2)
    }

    func testMissingRowReportsZeroUpdatedAtWhenRowStaysMissing() throws {
        let reader = NoticeReader(fetch: { _ in nil }, screen: { _ in Fixture.fullText })
        let result = try reader.read(chatId: Fixture.chatId)
        XCTAssertEqual(result.text, Fixture.fullText)
        XCTAssertEqual(result.updatedAt, 0)
    }

    func testMissingRowWithoutScreenNoticeIsNotFound() {
        for screenText: String? in [nil, ""] {
            let reader = NoticeReader(fetch: { _ in nil }, screen: { _ in screenText })
            XCTAssertThrowsError(try reader.read(chatId: Fixture.chatId)) {
                XCTAssertEqual($0 as? KktError, .notFound(String(Fixture.chatId)))
            }
        }
    }

    func testMissingRowKeepsScreenFailureReason() {
        for error in [KktError.chatWindowOpen, .kakaoInUse, .busy] {
            let reader = NoticeReader(fetch: { _ in nil }, screen: { _ in throw error })
            XCTAssertThrowsError(try reader.read(chatId: Fixture.chatId)) {
                XCTAssertEqual($0 as? KktError, error)
            }
        }
    }

    func testScreenFailurePreservesPreview() throws {
        for screenText: String? in [nil, ""] {
            let reader = NoticeReader(fetch: { _ in self.notice(Fixture.preview) }, screen: { _ in screenText })
            let result = try reader.read(chatId: Fixture.chatId)
            XCTAssertEqual(result.text, Fixture.preview)
            XCTAssertEqual(result.source, "truncated")
            XCTAssertTrue(result.truncated)
            XCTAssertEqual(result.updatedAt, Fixture.updatedAt)
            XCTAssertEqual(result.exitCode, 0)
        }
    }

    func testNoticeOutputContract() throws {
        let result = notice(Fixture.fullText)
        let line = KktOutput.line(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["chatId", "text", "source", "truncated", "updatedAt"])
        XCTAssertTrue(line.contains("\"chatId\":18000000000000001"))
        XCTAssertEqual(object["text"] as? String, Fixture.fullText)
        XCTAssertEqual(object["updatedAt"] as? Int64, Fixture.updatedAt)
        XCTAssertTrue(result.humanReadable.hasSuffix(Fixture.fullText))
    }

    func testScreenWaitsForWindowAndFullText() throws {
        let effects = ScreenEffects()
        let start = effects.now
        var dependencies = effects.dependencies()
        dependencies.windows = { _ in
            effects.now.timeIntervalSince(start) < 1 ? [effects.room] : [effects.room, effects.board]
        }
        let readValue = dependencies.value
        dependencies.value = { element in
            if CFEqual(element, effects.body), effects.now.timeIntervalSince(start) < 2 { return nil }
            return readValue(element)
        }
        XCTAssertEqual(try NoticeAX(dependencies: dependencies).read(Fixture.target), Fixture.fullText)
        XCTAssertGreaterThanOrEqual(effects.now.timeIntervalSince(start), 2)
        XCTAssertLessThanOrEqual(effects.now.timeIntervalSince(start), 3 + KktConstants.foregroundSettle)
        XCTAssertEqual(effects.clicks.count, 1)
        XCTAssertEqual(Array(effects.events.suffix(3)), ["restore", "close(board)", "close(room)"])
    }

    func testScreenTimeoutRestoresFocusAndClosesOnlyRoom() throws {
        let effects = ScreenEffects()
        let start = effects.now
        var dependencies = effects.dependencies()
        dependencies.windows = { _ in [effects.room] }
        XCTAssertNil(try NoticeAX(dependencies: dependencies).read(Fixture.target))
        XCTAssertEqual(effects.now.timeIntervalSince(start), 3 + KktConstants.foregroundSettle, accuracy: 0.001)
        XCTAssertEqual(effects.clicks.count, 1)
        XCTAssertEqual(Array(effects.events.suffix(2)), ["restore", "close(room)"])
    }

    func testScreenRequiresNoticeMarkerInBodyCell() throws {
        let effects = ScreenEffects()
        var dependencies = effects.dependencies()
        let readValue = dependencies.value
        dependencies.value = { CFEqual($0, effects.marker) ? "일반 글" : readValue($0) }
        XCTAssertNil(try NoticeAX(dependencies: dependencies).read(Fixture.target))
        XCTAssertEqual(Array(effects.events.suffix(3)), ["restore", "close(board)", "close(room)"])
    }

    func testScreenFailuresRestoreFocusAndCloseRoom() {
        for failure in ["raise", "activate", "click"] {
            let effects = ScreenEffects()
            var dependencies = effects.dependencies()
            switch failure {
            case "raise": dependencies.raise = { _ in false }
            case "activate": dependencies.activate = { throw KktError.automation("activation_failed") }
            default: dependencies.click = { _ in throw KktError.automation("click_failed") }
            }
            XCTAssertThrowsError(try NoticeAX(dependencies: dependencies).read(Fixture.target))
            XCTAssertEqual(Array(effects.events.suffix(2)), ["restore", "close(room)"])
        }
    }

    func testBannerMustFollowIconAndHaveNoIdentifier() throws {
        for invalid in ["identifier", "icon", "order", "position"] {
            let effects = ScreenEffects()
            var dependencies = effects.dependencies()
            let identifier = dependencies.identifier
            switch invalid {
            case "identifier":
                dependencies.identifier = { CFEqual($0, effects.banner) ? "unrelated" : identifier($0) }
            case "icon": dependencies.description = { _ in "unrelated" }
            case "order": dependencies.children = { _ in [] }
            default: dependencies.position = { _ in nil }
            }
            XCTAssertNil(try NoticeAX(dependencies: dependencies).read(Fixture.target))
            XCTAssertTrue(effects.clicks.isEmpty)
            XCTAssertEqual(effects.events, ["open", "close(room)"])
        }
    }

    func testNarrowBannerAndUnavailableVisibleRows() throws {
        let effects = ScreenEffects()
        var dependencies = effects.dependencies()
        dependencies.size = { _ in CGSize(width: 20, height: 30) }
        dependencies.visibleRows = { _ in nil }
        let children = dependencies.children
        dependencies.children = { CFEqual($0, effects.table) ? [effects.row] : children($0) }
        XCTAssertEqual(try NoticeAX(dependencies: dependencies).read(Fixture.target), Fixture.fullText)
        XCTAssertEqual(effects.clicks, [CGPoint(x: 110, y: 215)])
    }

    func testAvailableEmptyVisibleRowsDoNotReadTableChildren() throws {
        let effects = ScreenEffects()
        var dependencies = effects.dependencies()
        dependencies.visibleRows = { _ in [] }
        XCTAssertNil(try NoticeAX(dependencies: dependencies).read(Fixture.target))
        XCTAssertEqual(Array(effects.events.suffix(3)), ["restore", "close(board)", "close(room)"])
    }

    func testScreenDoesNotClickOrClosePreexistingNoticeWindow() {
        let effects = ScreenEffects()
        var dependencies = effects.dependencies()
        dependencies.windows = { _ in [effects.room, effects.board] }
        XCTAssertThrowsError(try NoticeAX(dependencies: dependencies).read(Fixture.target)) {
            XCTAssertEqual($0 as? KktError, .chatWindowOpen)
        }
        XCTAssertTrue(effects.clicks.isEmpty)
        XCTAssertEqual(effects.events, ["open", "close(room)"])
    }

    private func notice(_ text: String, deleted: Bool = false) -> NoticeResult {
        NoticeResult(chatId: Fixture.chatId, text: text, source: "database", truncated: false,
                     updatedAt: Fixture.updatedAt, messageDeleted: deleted)
    }

    private func noticeDatabase(rows: String) throws -> KakaoDatabase {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &writer), SQLITE_OK)
        let handle = try XCTUnwrap(writer)
        defer { sqlite3_close(handle) }
        let schema = """
            CREATE TABLE NTChatMessage (logId INTEGER, chatId INTEGER, type INTEGER, attachment TEXT, sentAt INTEGER);
            INSERT INTO NTChatMessage VALUES \(rows);
            """
        XCTAssertEqual(sqlite3_exec(handle, schema, nil, nil, nil), SQLITE_OK)
        return try KakaoDatabase.open(databasePath: path)
    }

    private final class ScreenEffects {
        let app = AXUIElementCreateApplication(-1)
        let room = AXUIElementCreateApplication(-2)
        let icon = AXUIElementCreateApplication(-3)
        let banner = AXUIElementCreateApplication(-4)
        let board = AXUIElementCreateApplication(-5)
        let table = AXUIElementCreateApplication(-6)
        let row = AXUIElementCreateApplication(-7)
        let cell = AXUIElementCreateApplication(-8)
        let marker = AXUIElementCreateApplication(-9)
        let body = AXUIElementCreateApplication(-10)
        let comment = AXUIElementCreateApplication(-11)
        let register = AXUIElementCreateApplication(-12)
        // 26.9 has an action-less button between the notice icon and its text (measured 2026-11-03).
        let spacer = AXUIElementCreateApplication(-13)
        var events: [String] = []
        var clicks: [CGPoint] = []
        var now = Date(timeIntervalSince1970: TimeInterval(Fixture.updatedAt))

        func dependencies() -> NoticeAX.Dependencies {
            var dependencies = NoticeAX.Dependencies()
            dependencies.open = { target in
                XCTAssertEqual(target, Fixture.target)
                self.events.append("open")
                return self.room
            }
            dependencies.runningPid = { -1 }
            dependencies.appElement = { _ in self.app }
            dependencies.windows = { _ in
                self.clicks.isEmpty ? [self.room] : [self.room, self.board]
            }
            dependencies.children = { element in
                if CFEqual(element, self.room) { return [self.icon, self.spacer, self.banner, self.register] }
                if CFEqual(element, self.board) { return [self.comment, self.register, self.table] }
                if CFEqual(element, self.table) { XCTFail("Use visible rows"); return [] }
                if CFEqual(element, self.row) { return [self.cell] }
                if CFEqual(element, self.cell) { return [self.marker, self.body, self.comment] }
                return []
            }
            dependencies.role = { element in
                if CFEqual(element, self.icon) { return "AXImage" }
                if CFEqual(element, self.banner) || CFEqual(element, self.marker) { return "AXStaticText" }
                if CFEqual(element, self.body) || CFEqual(element, self.comment) { return "AXTextArea" }
                if CFEqual(element, self.table) { return "AXTable" }
                if CFEqual(element, self.row) { return "AXRow" }
                if CFEqual(element, self.cell) { return "AXCell" }
                if CFEqual(element, self.register) || CFEqual(element, self.spacer) { return "AXButton" }
                return "AXWindow"
            }
            dependencies.identifier = { element in
                if CFEqual(element, self.board) { return "_NS:17" }
                if CFEqual(element, self.table) { return "_NS:95" }
                if CFEqual(element, self.marker) { return "_NS:57" }
                if CFEqual(element, self.comment) { return "_NS:27" }
                if CFEqual(element, self.register) { return "_NS:68" }
                return nil
            }
            dependencies.description = { CFEqual($0, self.icon) ? "chatroom icon noti dark" : nil }
            dependencies.value = { element in
                if CFEqual(element, self.body) { return Fixture.fullText }
                if CFEqual(element, self.marker) { return "23시간 전 ・ 공지" }
                if CFEqual(element, self.comment) { XCTFail("Do not read comment input") }
                return nil
            }
            dependencies.position = { element in
                XCTAssertTrue(CFEqual(element, self.banner))
                return CGPoint(x: 100, y: 200)
            }
            dependencies.size = { _ in CGSize(width: 200, height: 30) }
            dependencies.visibleRows = { element in
                XCTAssertTrue(CFEqual(element, self.table))
                return [self.row]
            }
            dependencies.captureFocus = { restoresCursor in
                XCTAssertTrue(restoresCursor)
                self.events.append("capture(cursor)")
                return { self.events.append("restore") }
            }
            dependencies.raise = { element in
                XCTAssertTrue(CFEqual(element, self.room))
                self.events.append("raise")
                return true
            }
            dependencies.activate = { self.events.append("activate") }
            dependencies.click = { point in self.clicks.append(point); self.events.append("click") }
            dependencies.close = { element in
                if CFEqual(element, self.board) { self.events.append("close(board)") }
                else if CFEqual(element, self.room) { self.events.append("close(room)") }
                else { XCTFail("Only close owned windows") }
            }
            dependencies.clock = { self.now }
            dependencies.sleep = { self.now.addTimeInterval($0) }
            return dependencies
        }
    }
}
