import CSQLCipher
import Foundation

public struct ReadChat: Encodable {
    public let id: Int64
    public let type: String
    public var displayName: String
    public let memberCount: Int
    public let lastMessageAt: String?
    public let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, type
        case displayName = "display_name", memberCount = "member_count"
        case lastMessageAt = "last_message_at", unreadCount = "unread_count"
    }
}

public struct ReadMessage: Encodable {
    public let id: Int64
    public let chatId: Int64
    public let senderId: Int64
    public let sender: String?
    public let text: String?
    public let type: String
    public let timestamp: String
    public let isFromMe: Bool

    enum CodingKeys: String, CodingKey {
        case id, sender, text, type, timestamp
        case chatId = "chat_id", senderId = "sender_id", isFromMe = "is_from_me"
    }
}

public enum ReadValue: Encodable {
    case integer(Int64), real(Double), text(String), null

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let value): try container.encode(value)
        case .real(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var description: String {
        switch self {
        case .integer(let value): String(value)
        case .real(let value): String(value)
        case .text(let value): value
        case .null: KktConstants.emptyText
        }
    }
}

public struct ReadQueryResult {
    public let columns: [String]
    public let rows: [[ReadValue]]
}

public struct ChatNameResolution {
    public let chatId: Int64?
    public let candidates: [ReadChat]
    public var exitCode: Int32 {
        chatId == nil ? KktConstants.Read.ambiguousExitCode : KktConstants.successExitCode
    }
}

public struct ReadQueries {
    private let database: KakaoDatabase

    public init(database: KakaoDatabase) { self.database = database }

    public static func retry<T>(
        sleep: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:), operation: () throws -> T
    ) throws -> T {
        var attempts = KktConstants.zero
        while true {
            do { return try operation() }
            catch KktError.busy {
                attempts += KktConstants.one
                guard attempts < KktConstants.Read.attempts else { throw KktError.databaseUnavailable }
                sleep(KktConstants.Read.retryDelay)
            }
        }
    }

    public static func parseSince(_ value: String, now: Date = Date()) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let unit = trimmed.last, let multiplier = KktConstants.Read.durationUnits[unit],
              let count = Double(trimmed.dropLast()), count.isFinite, count >= KktConstants.zeroInterval else { return nil }
        let seconds = count * multiplier
        guard seconds.isFinite else { return nil }
        return now.addingTimeInterval(-seconds)
    }

    public func chats(limit: Int = KktConstants.Read.defaultLimit) throws -> [ReadChat] {
        typealias C = KktConstants.ReadColumn
        let records = try database.query(KktConstants.ReadQueries.chats, bind: [.int(limit)]) { row in
            (ReadChat(id: row.int64(C.id), type: KktConstants.Read.roomTypes[row.int(C.type)] ?? KktConstants.Read.unknown,
                      displayName: row.string(C.name) ?? KktConstants.emptyText, memberCount: row.int(C.memberCount),
                      lastMessageAt: row.optionalKakaoDate(C.updatedAt).map { ISO8601DateFormatter().string(from: $0) },
                      unreadCount: row.int(C.unread)), row.string(C.members))
        }
        var users: [Int64: String] = [:]
        if records.contains(where: { $0.0.displayName.isEmpty }) {
            let names = try database.query(KktConstants.ReadNames.usersQuery, bind: []) {
                ($0.int64(C.id), $0.string(C.type))
            }
            for (id, name) in names where users[id] == nil {
                if let name { users[id] = name }
            }
        }
        return records.map { chat, hex in
            var chat = chat
            if chat.displayName.isEmpty {
                chat.displayName = RoomNames.memberName(hex: hex, memberCount: chat.memberCount, users: users)
                    ?? KktConstants.ReadNames.unknown
            }
            return chat
        }
    }

    public func resolveChat(named name: String) throws -> ChatNameResolution {
        let needle = name.precomposedStringWithCanonicalMapping
        let hits = try chats(limit: KktConstants.ReadNames.allRoomsLimit).filter {
            $0.displayName.precomposedStringWithCanonicalMapping.contains(needle)
        }
        let exact = hits.filter { $0.displayName.precomposedStringWithCanonicalMapping == needle }
        let picks = exact.count == KktConstants.one ? exact : hits
        return ChatNameResolution(chatId: picks.count == KktConstants.one ? picks.first?.id : nil, candidates: picks)
    }

    public func messages(
        chatId: Int64, since: Date? = nil, limit: Int = KktConstants.Read.defaultLimit
    ) throws -> [ReadMessage] {
        try readMessages(chatId: chatId, since: since, limit: limit, text: nil)
    }

    public func search(
        text: String, chatId: Int64? = nil, since: Date? = nil, limit: Int = KktConstants.Read.searchLimit
    ) throws -> [ReadMessage] {
        try readMessages(chatId: chatId, since: since, limit: limit, text: text)
    }

    private func readMessages(chatId: Int64?, since: Date?, limit: Int, text: String?) throws -> [ReadMessage] {
        typealias Q = KktConstants.ReadQueries
        typealias C = KktConstants.ReadMessageColumn
        var conditions: [String] = []
        var bindings: [SQLValue] = []
        if let chatId { conditions.append(Q.chatFilter); bindings.append(.int64(chatId)) }
        if let since { conditions.append(Q.sinceFilter); bindings.append(.double(since.timeIntervalSince1970)) }
        if let text {
            conditions.append(Q.textFilter)
            bindings.append(.string(Q.wildcard + text + Q.wildcard))
        }
        bindings.append(.int(limit))
        let sql = Q.messages + Q.whereClause + conditions.joined(separator: Q.and) + Q.messageOrder
        let myUserId = try database.myUserId()
        return try database.query(sql, bind: bindings) { row in
            ReadMessage(id: row.int64(C.id), chatId: row.int64(C.chatId), senderId: row.int64(C.senderId),
                        sender: row.string(C.sender), text: row.string(C.text),
                        type: KktConstants.Read.messageTypes[row.int(C.type)] ?? KktConstants.Read.unknown,
                        timestamp: ISO8601DateFormatter().string(from: row.kakaoDate(C.timestamp)),
                        isFromMe: row.int64(C.senderId) == myUserId)
        }
    }

    public func query(_ sql: String) throws -> ReadQueryResult {
        try ReadOnlySQL.validate(sql)
        var columns: [String] = []
        let rows = try database.query(sql, bind: []) { row in
            let indices = KktConstants.zeroColumn..<sqlite3_column_count(row.statement)
            if columns.isEmpty {
                columns = indices.map { String(cString: sqlite3_column_name(row.statement, $0)) }
            }
            return indices.map { index -> ReadValue in
                switch sqlite3_column_type(row.statement, index) {
                case SQLITE_INTEGER: return .integer(row.int64(index))
                case SQLITE_FLOAT: return .real(row.double(index))
                case SQLITE_TEXT: return .text(row.string(index) ?? KktConstants.emptyText)
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(row.statement, index))
                    guard let pointer = sqlite3_column_blob(row.statement, index) else { return .text(KktConstants.emptyText) }
                    let data = Data(bytes: pointer, count: count)
                    return .text(data.map { String(format: KktConstants.hexFormat, $0) }.joined())
                default: return .null
                }
            }
        }
        return ReadQueryResult(columns: columns, rows: rows)
    }
}

extension KktConstants {
    public enum Read {
        public static let chatsCommand = "chats"
        public static let messagesCommand = "messages"
        public static let searchCommand = "search"
        public static let queryCommand = "query"
        public static let chatOption = "chat"
        public static let chatIdOption = "chat-id"
        public static let sinceOption = "since"
        public static let limitOption = "limit"
        public static let jsonOption = "json"
        public static let defaultLimit = 50
        public static let searchLimit = 20
        public static let ambiguousExitCode: Int32 = 2
        public static let invalidTarget = "Exactly one of --chat-id or --chat is required."
        public static let invalidSince = "Invalid --since duration (use 7d, 12h or 30m)."
        public static let invalidLimit = "--limit must be positive."
        static let attempts = 3
        static let retryDelay: TimeInterval = 0.1
        static let durationUnits: [Character: TimeInterval] = ["s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800]
        static let roomTypes = [0: "direct", 1: "group", 4: "open", 5: "self"]
        static let messageTypes = [0: "system", 1: "text", 2: "photo", 3: "video", 4: "voice", 5: "sticker", 6: "file", 7: "location"]
        static let unknown = "unknown"
    }

    enum ReadColumn {
        static let id: Int32 = 0
        static let type: Int32 = 1
        static let name: Int32 = 2
        static let memberCount: Int32 = 3
        static let updatedAt: Int32 = 4
        static let unread: Int32 = 5
        static let members: Int32 = 6
    }

    enum ReadQueries {
        static let chats = """
            SELECT r.chatId, r.type, \(RoomNames.displayNameExpression), r.activeMembersCount,
                   r.lastUpdatedAt, r.countOfNewMessage, hex(r.displayMemberIds)
            \(roomJoins) ORDER BY r.lastUpdatedAt DESC, r.chatId LIMIT ?
            """
        static let messages = """
            SELECT m.logId, m.chatId, m.authorId,
                   COALESCE(NULLIF(a.friendNickName,''), NULLIF(a.displayName,''), NULLIF(a.nickName,''),
                            NULLIF(fallback.friendNickName,''), NULLIF(fallback.displayName,''), NULLIF(fallback.nickName,'')),
                   m.message, m.type, m.sentAt
            FROM NTChatMessage m
            LEFT JOIN NTChatRoom r ON r.chatId=m.chatId
            LEFT JOIN NTUser a ON a.userId=m.authorId AND a.linkId=COALESCE(r.linkId,0)
            LEFT JOIN NTUser fallback ON fallback.userId=m.authorId AND fallback.linkId=0
            """
        static let chatFilter = "m.chatId=?"
        static let sinceFilter = "m.sentAt>=?"
        static let textFilter = "m.message LIKE ?"
        static let wildcard = "%"
        static let whereClause = " WHERE "
        static let and = " AND "
        static let messageOrder = " ORDER BY m.sentAt DESC, m.logId DESC LIMIT ?"
    }

    enum ReadMessageColumn {
        static let id: Int32 = 0
        static let chatId: Int32 = 1
        static let senderId: Int32 = 2
        static let sender: Int32 = 3
        static let text: Int32 = 4
        static let type: Int32 = 5
        static let timestamp: Int32 = 6
    }
}
