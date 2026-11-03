import Foundation

public struct ServeCursor {
    public var lastLogId: Int64

    public init(lastLogId: Int64) {
        self.lastLogId = lastLogId
    }

    public mutating func advance(with events: [KktEvent]) {
        for event in events where event.event == KktConstants.messageEvent {
            if let logId = event.logId { lastLogId = max(lastLogId, logId) }
        }
    }
}

public final class ServeLoop {
    private struct PendingScrap {
        let chatId: Int64
        let logId: Int64
        let sentAt: Int64
    }

    private let fetch: (Int64, Int) throws -> [KktEvent]
    private let fetchAttachment: (Int64, Int64) throws -> String?
    private let maxLogId: () throws -> Int64
    private let emit: (String) -> Void
    private let sleep: (TimeInterval) -> Void
    private let clock: () -> Date
    private let interval: TimeInterval
    private let shouldContinue: () -> Bool

    public init(
        fetch: @escaping (Int64, Int) throws -> [KktEvent],
        fetchAttachment: @escaping (Int64, Int64) throws -> String? = { _, _ in nil },
        maxLogId: @escaping () throws -> Int64,
        emit: @escaping (String) -> Void,
        sleep: @escaping (TimeInterval) -> Void,
        clock: @escaping () -> Date,
        interval: TimeInterval,
        shouldContinue: @escaping () -> Bool = { true }
    ) {
        self.fetch = fetch
        self.fetchAttachment = fetchAttachment
        self.maxLogId = maxLogId
        self.emit = emit
        self.sleep = sleep
        self.clock = clock
        self.interval = interval
        self.shouldContinue = shouldContinue
    }

    public func run(since: Int64?) -> Int32 {
        do {
            return poll(cursor: ServeCursor(lastLogId: try since ?? maxLogId()))
        } catch {
            return fail()
        }
    }

    private func poll(cursor initialCursor: ServeCursor) -> Int32 {
        var cursor = initialCursor
        var errors = KktConstants.initialErrorCount
        var lastHeartbeat = clock()
        var pending: [PendingScrap] = []
        while shouldContinue() {
            do {
                let events = try fetch(cursor.lastLogId, KktConstants.serveBatchLimit)
                errors = KktConstants.initialErrorCount
                for event in events {
                    emit(KktOutput.line(event))
                    trackScrap(event, pending: &pending)
                }
                cursor.advance(with: events)
                pollScraps(pending: &pending)
                heartbeat(cursor: cursor, lastHeartbeat: &lastHeartbeat)
                if events.count == KktConstants.serveBatchLimit { continue }
            } catch {
                errors += KktConstants.errorCountIncrement
                if errors >= KktConstants.serveMaxConsecutiveErrors { return fail() }
                pollScraps(pending: &pending)
                heartbeat(cursor: cursor, lastHeartbeat: &lastHeartbeat)
            }
            sleep(interval)
        }
        return KktConstants.successExitCode
    }

    private func trackScrap(_ event: KktEvent, pending: inout [PendingScrap]) {
        guard event.event == KktConstants.messageEvent, event.type == KktConstants.scrapMessageType,
              let chatId = event.chatId, let logId = event.logId, let sentAt = event.sentAt,
              let attachment = event.attachment, let fields = attachmentFields(attachment),
              fields[KktConstants.scrapURLsKey] != nil, fields[KktConstants.scrapDataKey] == nil
        else { return }
        // KakaoTalk server time can run slightly ahead of the local clock, so a negative age is still a fresh message.
        let age = clock().timeIntervalSince1970 - TimeInterval(sentAt)
        guard age <= KktConstants.scrapWatchSeconds,
              !pending.contains(where: { $0.chatId == chatId && $0.logId == logId }) else { return }
        pending.append(PendingScrap(chatId: chatId, logId: logId, sentAt: sentAt))
        if pending.count > KktConstants.scrapPendingMax {
            pending.removeFirst(pending.count - KktConstants.scrapPendingMax)
        }
    }

    private func pollScraps(pending: inout [PendingScrap]) {
        let now = clock().timeIntervalSince1970
        pending.removeAll { entry in
            if now - TimeInterval(entry.sentAt) > KktConstants.scrapWatchSeconds { return true }
            guard let attachment = try? fetchAttachment(entry.chatId, entry.logId),
                  let fields = attachmentFields(attachment), fields[KktConstants.scrapDataKey] != nil
            else { return false }
            emit(KktOutput.line(KktEvent.scrap(
                logId: entry.logId, chatId: entry.chatId, attachment: attachment
            )))
            return true
        }
    }

    private func attachmentFields(_ attachment: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(attachment.utf8))) as? [String: Any]
    }

    private func heartbeat(cursor: ServeCursor, lastHeartbeat: inout Date) {
        let now = clock()
        guard now.timeIntervalSince(lastHeartbeat) >= KktConstants.serveHeartbeatSeconds else { return }
        emit(KktOutput.line(KktEvent.heartbeat(maxLogId: cursor.lastLogId)))
        lastHeartbeat = now
    }

    private func fail() -> Int32 {
        emit(KktOutput.line(KktEvent.error(reason: KktConstants.databaseUnavailableCode)))
        return KktConstants.failureExitCode
    }
}
