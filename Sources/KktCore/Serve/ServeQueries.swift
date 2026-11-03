import Foundation

extension KakaoDatabase {
    public func eventsAfter(logId: Int64, limit: Int, myUserId: Int64) throws -> [KktEvent] {
        typealias Column = KktConstants.ServeColumn
        let events = try query(KktConstants.serveEventsQuery, bind: [.int64(logId), .int64(KktConstants.pendingLogIdSentinel), .int(limit)]) { row in
            KktEvent.message(
                logId: row.int64(Column.logId), chatId: row.int64(Column.chatId),
                chatName: row.string(Column.chatName), chatType: row.int(Column.chatType),
                linkId: row.int64(Column.linkId), authorId: row.int64(Column.authorId),
                authorName: row.string(Column.authorName),
                isFromMe: row.int64(Column.authorId) == myUserId, type: row.int(Column.type),
                text: row.string(Column.text), attachment: row.string(Column.attachment),
                sentAt: row.int64(Column.sentAt)
            )
        }
        return events
    }

    public func currentMaxLogId() throws -> Int64 {
        let results = try query(KktConstants.serveMaxLogIdQuery, bind: [.int64(KktConstants.pendingLogIdSentinel)]) { row in
            row.optionalInt64(KktConstants.zeroColumn)
        }
        let logId = results.first.flatMap { $0 } ?? KktConstants.noLogId
        return logId
    }

    public func scrapAttachment(chatId: Int64, logId: Int64) throws -> String? {
        let rows = try query(KktConstants.scrapAttachmentQuery, bind: [.int64(chatId), .int64(logId)]) { row in
            row.string(KktConstants.scrapAttachmentColumn)
        }
        return rows.first.flatMap { $0 }
    }

    public func myUserId() throws -> Int64 {
        let results = try query(KktConstants.serveUserIdQuery, bind: []) { row in
            row.int64(KktConstants.zeroColumn)
        }
        return results.first ?? KktConstants.noLogId
    }
}
