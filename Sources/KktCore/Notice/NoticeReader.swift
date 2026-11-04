import Foundation

public struct NoticeResult: Encodable, Equatable {
    public let chatId: Int64
    public let text: String
    public let source: String
    public let truncated: Bool
    public let updatedAt: Int64
    public let messageDeleted: Bool
    public var exitCode: Int32 { KktConstants.successExitCode }
    public var humanReadable: String {
        KktConstants.Notice.heading + KktConstants.newline
            + [String(chatId), source, String(truncated), String(updatedAt)]
                .joined(separator: KktConstants.Notice.separator)
            + KktConstants.newline + text
    }

    private enum CodingKeys: String, CodingKey {
        case chatId, text, source, truncated, updatedAt
    }

    public init(chatId: Int64, text: String, source: String, truncated: Bool, updatedAt: Int64,
                messageDeleted: Bool = false) {
        self.chatId = chatId
        self.text = text
        self.source = source
        self.truncated = truncated
        self.updatedAt = updatedAt
        self.messageDeleted = messageDeleted
    }
}

public struct NoticeReader {
    private let fetch: (Int64) throws -> NoticeResult?
    private let screen: (Int64) throws -> String?

    public init(fetch: @escaping (Int64) throws -> NoticeResult?, screen: @escaping (Int64) throws -> String?) {
        self.fetch = fetch
        self.screen = screen
    }

    public func read(chatId: Int64) throws -> NoticeResult {
        guard let notice = try fetch(chatId) else { return try readWithoutRow(chatId: chatId) }
        // KakaoTalk caps the stored preview at 500 UTF-16 units (measured); Swift Characters merge "\r\n" and undercount.
        guard notice.messageDeleted || notice.text.utf16.count >= KktConstants.Notice.truncationThreshold else {
            return notice
        }
        if let text = try? screen(chatId), !text.isEmpty {
            return NoticeResult(chatId: chatId, text: text, source: KktConstants.Notice.screen,
                                truncated: false, updatedAt: notice.updatedAt)
        }
        return NoticeResult(chatId: chatId, text: notice.text, source: KktConstants.Notice.truncated,
                            truncated: true, updatedAt: notice.updatedAt)
    }

    private func readWithoutRow(chatId: Int64) throws -> NoticeResult {
        guard let text = try screen(chatId), !text.isEmpty else { throw KktError.notFound(String(chatId)) }
        let updatedAt = (try? fetch(chatId))?.updatedAt ?? KktConstants.Notice.unknownUpdatedAt
        return NoticeResult(chatId: chatId, text: text, source: KktConstants.Notice.screen,
                            truncated: false, updatedAt: updatedAt)
    }

    public static func databaseNotice(database: KakaoDatabase, chatId: Int64) throws -> NoticeResult? {
        let notices = try database.query(KktConstants.Notice.query, bind: [.int64(chatId)]) { row -> NoticeResult? in
            guard let attachment = row.string(KktConstants.Notice.attachmentColumn),
                  let object = try? JSONSerialization.jsonObject(with: Data(attachment.utf8)) as? [String: Any],
                  let objects = object[KktConstants.Notice.objectsKey] as? [[String: Any]],
                  let text = objects.first(where: {
                      $0[KktConstants.Notice.typeKey] as? Int == KktConstants.Notice.noticeType
                  })?[KktConstants.Notice.contentKey] as? String else { return nil }
            let type = row.int64(KktConstants.Notice.typeColumn)
            return NoticeResult(chatId: chatId, text: text, source: KktConstants.Notice.database,
                                truncated: false, updatedAt: row.int64(KktConstants.Notice.updatedAtColumn),
                                messageDeleted: type & KktConstants.Notice.deletedTypeFlag != .zero)
        }
        return notices.lazy.compactMap { $0 }.first
    }

    public static func screenTarget(database: KakaoDatabase, chatId: Int64) throws -> SendTarget {
        guard let room = try database.room(chatId: chatId) else { throw KktError.notFound(String(chatId)) }
        let rooms = try ReadQueries(database: database).chats(limit: KktConstants.ReadNames.allRoomsLimit)
        let name = room.type == KktConstants.selfRoomType ? room.displayName
            : rooms.first(where: { $0.id == chatId })?.displayName ?? room.displayName
        let targetRoom = RoomRow(chatId: room.chatId, type: room.type, linkId: room.linkId,
                                 linkUrl: room.linkUrl, displayName: name)
        let count = rooms.filter {
            $0.displayName.precomposedStringWithCanonicalMapping == name.precomposedStringWithCanonicalMapping
        }.count
        return try resolveTarget(chatId: chatId, room: targetRoom, sameNameCount: count)
    }
}

extension KktConstants {
    public enum Notice {
        public static let command = "notice"
        public static let database = "database"
        public static let screen = "screen"
        public static let truncated = "truncated"
        public static let heading = "chatId / source / truncated / updatedAt"
        public static let separator = " / "
        static let truncationThreshold = 490
        static let unknownUpdatedAt: Int64 = 0
        static let objectsKey = "os"
        static let typeKey = "t"
        static let contentKey = "ct"
        static let noticeType = 1
        static let attachmentColumn: Int32 = 0
        static let updatedAtColumn: Int32 = 1
        static let typeColumn: Int32 = 2
        static let deletedTypeFlag: Int64 = 16384
        static let query = """
            SELECT attachment, sentAt, type FROM NTChatMessage
            WHERE chatId=? AND (type & 16383)=24 ORDER BY logId DESC
            """
    }
}
