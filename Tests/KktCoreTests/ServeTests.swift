import CoreFoundation
import Foundation
import KktCore
import XCTest

final class ServeTests: XCTestCase {
    private enum Fixture {
        static let largeLogId: Int64 = 9_007_199_254_740_993
        static let largeChatId: Int64 = 18_000_000_000_000_001
        static let largeLogField = #""logId":9007199254740993"#
        static let largeChatField = #""chatId":18000000000000001"#
        static let busyBeforeSuccess = 29
        static let total = 1_200
        static let pages = [500, 500, 200]
        static let zero: Int64 = 0
        static let first: Int64 = 1
        static let chatId: Int64 = 42
        static let chatType = 2
        static let linkId: Int64 = 99
        static let authorId: Int64 = 7
        static let messageType = 1
        static let timestamp: Int64 = 1_793_577_600
        static let chatName = "그룹/이름"
        static let authorName = "작성자"
        static let text = "메시지\n다음 줄"
        static let attachment = #"{"url":"https://example.com/image"}"#
        static let heartbeatElapsed: TimeInterval = 31
        static let transientErrors = 2
        static let errorLine = #"{"event":"error","reason":"database_unavailable"}"#
        static let heartbeatLine = #"{"event":"heartbeat","maxLogId":42}"#
        static let fields = [
            "attachment", "authorId", "authorName", "chatId", "chatName", "chatType",
            "event", "isFromMe", "linkId", "logId", "sentAt", "text", "type",
        ]
        static let urls = #"{"urls":["https://example.com"]}"#
        static let preview = #"{"universalScrapData":{"title":"Example","image_url":"https://example.com/image","description":"Preview"},"urls":["https://example.com"]}"#
        static let scrapFields = ["attachment", "chatId", "event", "logId"]
        static let scrapEvent = "scrap"
        static let window: TimeInterval = 120
        static let pendingMax = 200
        static let increment = 1
        static let threePolls = 3
        static let otherType = 2
        static let urlsInText = #"{"text":"urls universalScrapData"}"#
    }

    private func message(_ logId: Int64) -> KktEvent {
        .message(
            logId: logId, chatId: Fixture.chatId, chatName: Fixture.chatName,
            chatType: Fixture.chatType, linkId: Fixture.linkId, authorId: Fixture.authorId,
            authorName: Fixture.authorName, isFromMe: true, type: Fixture.messageType,
            text: Fixture.text, attachment: Fixture.attachment, sentAt: Fixture.timestamp
        )
    }


    func testLargeIdsAreEmittedExactly() {
        let event = KktEvent.message(
            logId: Fixture.largeLogId, chatId: Fixture.largeChatId, chatType: Fixture.chatType,
            linkId: Fixture.linkId, authorId: Fixture.authorId, isFromMe: true,
            type: Fixture.messageType, sentAt: Fixture.timestamp
        )
        var emitted: [String] = []
        let loop = ServeLoop(
            fetch: { _, _ in [event] }, maxLogId: { Fixture.zero },
            emit: { emitted.append($0) }, sleep: { _ in }, clock: { Date.distantPast },
            interval: KktConstants.serveDefaultInterval, shouldContinue: { emitted.isEmpty }
        )
        XCTAssertEqual(loop.run(since: Fixture.zero), KktConstants.successExitCode)
        XCTAssertEqual(emitted.count, Fixture.increment)
        XCTAssertTrue(emitted.first?.contains(Fixture.largeLogField) == true)
        XCTAssertTrue(emitted.first?.contains(Fixture.largeChatField) == true)
    }

    func testServeSurvivesTransientBusyErrors() {
        var attempts = 0
        var emitted: [String] = []
        let event = message(Fixture.first)
        let loop = ServeLoop(
            fetch: { _, _ in
                attempts += Fixture.increment
                if attempts <= Fixture.busyBeforeSuccess { throw KktError.busy }
                return [event]
            }, maxLogId: { Fixture.zero }, emit: { emitted.append($0) }, sleep: { _ in },
            clock: { Date.distantPast }, interval: KktConstants.serveDefaultInterval,
            shouldContinue: { attempts <= Fixture.busyBeforeSuccess }
        )
        XCTAssertEqual(loop.run(since: Fixture.zero), KktConstants.successExitCode)
        XCTAssertEqual(attempts, Fixture.busyBeforeSuccess + Fixture.increment)
        XCTAssertEqual(emitted, [KktOutput.line(event)])
        assertFailureLimit()
    }

    func testServeCursorPagesInBatches() {
        var emitted: [String] = []
        var pageSizes: [Int] = []
        var cursors: [Int64] = []
        var sleepCounts: [Int] = []
        let loop = ServeLoop(
            fetch: { cursor, limit in
                cursors.append(cursor)
                XCTAssertTrue(sleepCounts.isEmpty)
                XCTAssertEqual(limit, KktConstants.serveBatchLimit)
                let upper = min(Int(cursor) + limit, Fixture.total)
                let page = ((Int(cursor) + Int(Fixture.first))...upper).map { self.message(Int64($0)) }
                pageSizes.append(page.count)
                return page
            },
            maxLogId: { XCTFail("Explicit cursor must skip MAX(logId)"); return Fixture.zero },
            emit: { emitted.append($0) },
            sleep: { interval in
                XCTAssertEqual(interval, KktConstants.serveDefaultInterval)
                sleepCounts.append(emitted.count)
            },
            clock: { Date(timeIntervalSince1970: TimeInterval(Fixture.zero)) },
            interval: KktConstants.serveDefaultInterval,
            shouldContinue: { sleepCounts.isEmpty }
        )
        XCTAssertEqual(loop.run(since: Fixture.zero), 0)
        XCTAssertEqual(pageSizes, Fixture.pages)
        XCTAssertEqual(cursors, [Fixture.zero, Int64(Fixture.pages[0]), Int64(Fixture.pages[0] * 2)])
        XCTAssertEqual(emitted.count, Fixture.total)
        XCTAssertEqual(sleepCounts, [Fixture.total])
    }

    func testServeEmitsHeartbeatEvery30s() {
        var now = Date(timeIntervalSince1970: TimeInterval(Fixture.zero))
        var emitted: [String] = []
        var fetches = 0
        let loop = ServeLoop(
            fetch: { cursor, _ in
                XCTAssertEqual(cursor, Fixture.chatId)
                fetches += 1
                return []
            },
            maxLogId: { Fixture.chatId }, emit: { emitted.append($0) },
            sleep: { _ in now.addTimeInterval(Fixture.heartbeatElapsed) }, clock: { now },
            interval: KktConstants.serveDefaultInterval,
            shouldContinue: { fetches < Fixture.transientErrors }
        )
        XCTAssertEqual(loop.run(since: nil), 0)
        XCTAssertEqual(emitted, [Fixture.heartbeatLine])
    }

    func testServeLoopSurvivesBusyThenFailsAfterLimit() {
        var attempts = 0
        var emitted: [String] = []
        var sleeps = 0
        let success = message(Fixture.first)
        let loop = ServeLoop(
            fetch: { _, _ in
                attempts += 1
                if attempts <= Fixture.transientErrors { throw KktError.busy }
                return [success]
            }, maxLogId: { Fixture.zero }, emit: { emitted.append($0) },
            sleep: { _ in sleeps += 1 }, clock: { Date.distantPast },
            interval: KktConstants.serveDefaultInterval,
            shouldContinue: { attempts <= Fixture.transientErrors }
        )
        XCTAssertEqual(loop.run(since: Fixture.zero), 0)
        XCTAssertEqual(emitted, [KktOutput.line(success)])
        XCTAssertEqual(sleeps, Fixture.transientErrors + 1)
        assertFailureLimit()
    }

    private func assertFailureLimit() {
        var attempts = 0
        var emitted: [String] = []
        let loop = ServeLoop(
            fetch: { _, _ in attempts += 1; throw KktError.busy },
            maxLogId: { Fixture.zero }, emit: { emitted.append($0) }, sleep: { _ in },
            clock: { Date.distantPast }, interval: KktConstants.serveDefaultInterval,
            shouldContinue: { attempts <= KktConstants.serveMaxConsecutiveErrors }
        )
        XCTAssertEqual(loop.run(since: Fixture.zero), 1)
        XCTAssertEqual(attempts, KktConstants.serveMaxConsecutiveErrors)
        XCTAssertEqual(emitted, [Fixture.errorLine])
    }

    func testEventEncodingFieldNames() throws {
        let line = KktOutput.line(message(Fixture.first))
        let data = try XCTUnwrap(line.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object.keys.sorted(), Fixture.fields)
        let sentAt = try XCTUnwrap(object["sentAt"] as? NSNumber)
        XCTAssertEqual(sentAt.int64Value, Fixture.timestamp)
        XCTAssertFalse(CFNumberIsFloatType(sentAt))
        XCTAssertEqual(object["attachment"] as? String, Fixture.attachment)
        XCTAssertFalse(line.contains("\n"))
        XCTAssertEqual(KktOutput.line(.heartbeat(maxLogId: Fixture.chatId) as KktEvent), Fixture.heartbeatLine)
        XCTAssertEqual(KktOutput.line(.error(reason: "database_unavailable") as KktEvent), Fixture.errorLine)
    }

    func testCursorAdvancesOnlyForMessagesAndNeverBackwards() {
        var cursor = ServeCursor(lastLogId: Fixture.chatId)
        cursor.advance(with: [.heartbeat(maxLogId: Int64(Fixture.total)), message(Fixture.first)])
        XCTAssertEqual(cursor.lastLogId, Fixture.chatId)
        cursor.advance(with: [message(Int64(Fixture.total)), message(Fixture.authorId)])
        XCTAssertEqual(cursor.lastLogId, Int64(Fixture.total))
    }

    func testSuccessfulPollResetsConsecutiveErrorCount() {
        var attempts = 0
        var emitted: [String] = []
        let recoveryPoll = KktConstants.serveMaxConsecutiveErrors
        let totalPolls = recoveryPoll + Fixture.transientErrors
        let loop = ServeLoop(
            fetch: { _, _ in
                attempts += 1
                if attempts == recoveryPoll { return [self.message(Fixture.first)] }
                throw KktError.busy
            }, maxLogId: { Fixture.zero }, emit: { emitted.append($0) }, sleep: { _ in },
            clock: { Date.distantPast }, interval: KktConstants.serveDefaultInterval,
            shouldContinue: { attempts < totalPolls }
        )
        XCTAssertEqual(loop.run(since: Fixture.zero), 0)
        XCTAssertEqual(attempts, totalPolls)
        XCTAssertEqual(emitted, [KktOutput.line(message(Fixture.first))])
    }

    private func linkMessage(
        _ logId: Int64 = Fixture.first, attachment: String? = Fixture.urls,
        age: TimeInterval = .zero, type: Int = Fixture.messageType
    ) -> KktEvent {
        KktEvent(
            event: "message", logId: logId, chatId: Fixture.chatId,
            type: type, attachment: attachment, sentAt: Fixture.timestamp - Int64(age)
        )
    }

    private func runScrap(
        events: [KktEvent], polls: Int = Fixture.threePolls,
        elapsedPerPoll: TimeInterval = .zero,
        read: @escaping (Int64, Int64, Int) throws -> String?
    ) -> [String] {
        var poll = 0
        var now = Date(timeIntervalSince1970: TimeInterval(Fixture.timestamp))
        var emitted: [String] = []
        let loop = ServeLoop(
            fetch: { _, _ in
                poll += Fixture.increment
                return poll == Fixture.increment ? events : []
            },
            fetchAttachment: { chatId, logId in try read(chatId, logId, poll) },
            maxLogId: { Fixture.zero }, emit: { emitted.append($0) },
            sleep: { _ in now.addTimeInterval(elapsedPerPoll) }, clock: { now },
            interval: KktConstants.serveDefaultInterval, shouldContinue: { poll < polls }
        )
        XCTAssertEqual(loop.run(since: Fixture.zero), KktConstants.successExitCode)
        XCTAssertEqual(poll, polls)
        return emitted
    }

    func testScrapUpdateEmittedOnceWhenPreviewArrives() throws {
        let event = linkMessage()
        var reads = 0
        let emitted = runScrap(events: [event]) { chatId, logId, poll in
            XCTAssertEqual(chatId, Fixture.chatId)
            XCTAssertEqual(logId, Fixture.first)
            reads += Fixture.increment
            return poll == Fixture.increment ? Fixture.urls : Fixture.preview
        }
        let expected = KktEvent(
            event: Fixture.scrapEvent, logId: Fixture.first,
            chatId: Fixture.chatId, attachment: Fixture.preview
        )
        XCTAssertEqual(emitted, [KktOutput.line(event), KktOutput.line(expected)])
        XCTAssertEqual(reads, Fixture.transientErrors)
        let data = try XCTUnwrap(emitted.last?.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object.keys.sorted(), Fixture.scrapFields)
        XCTAssertEqual(object["attachment"] as? String, Fixture.preview)
    }

    func testRowsWithoutUrlsAreNotTracked() {
        let events = [
            linkMessage(attachment: nil), linkMessage(attachment: Fixture.attachment),
            linkMessage(attachment: Fixture.preview), linkMessage(type: Fixture.otherType),
            linkMessage(attachment: Fixture.urlsInText),
        ]
        let emitted = runScrap(events: events) { _, _, _ in
            XCTFail("Only text messages with pending URL previews should be read")
            return nil
        }
        XCTAssertEqual(emitted, events.map(KktOutput.line))
    }

    func testOldBackfillRowsAreNotTracked() {
        let event = linkMessage(age: Fixture.window + TimeInterval(Fixture.increment))
        let emitted = runScrap(events: [event]) { _, _, _ in
            XCTFail("Old backfill must never be read")
            return nil
        }
        XCTAssertEqual(emitted, [KktOutput.line(event)])
    }

    func testPendingEntriesExpireAfterTheWindow() {
        var reads: [Int] = []
        let emitted = runScrap(
            events: [linkMessage()], elapsedPerPoll: Fixture.window
        ) { _, _, poll in
            reads.append(poll)
            return nil
        }
        XCTAssertEqual(reads, [Fixture.increment, Fixture.transientErrors])
        XCTAssertFalse(emitted.contains { $0.contains(Fixture.scrapEvent) })
    }

    func testPendingListIsCapped() {
        let total = Fixture.pendingMax + Fixture.increment
        let events = (Fixture.increment...total).map { linkMessage(Int64($0)) }
        var reads: [Int64] = []
        let emitted = runScrap(events: events, polls: Fixture.increment) { _, logId, _ in
            reads.append(logId)
            return nil
        }
        XCTAssertEqual(reads, (Fixture.transientErrors...total).map(Int64.init))
        XCTAssertEqual(emitted, events.map(KktOutput.line))
    }

    func testScrapReadFailureKeepsTheLoopAlive() {
        var reads = 0
        let event = linkMessage()
        let total = KktConstants.serveMaxConsecutiveErrors + Fixture.transientErrors
        let emitted = runScrap(events: [event], polls: total) { _, _, poll in
            reads += Fixture.increment
            if poll < total { throw KktError.busy }
            return Fixture.preview
        }
        XCTAssertEqual(reads, total)
        XCTAssertEqual(emitted, [KktOutput.line(event), KktOutput.line(KktEvent(
            event: Fixture.scrapEvent, logId: Fixture.first,
            chatId: Fixture.chatId, attachment: Fixture.preview
        ))])
    }
}
