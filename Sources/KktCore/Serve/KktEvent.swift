public struct KktEvent: Encodable, Equatable {
    public let event: String
    public let logId: Int64?
    public let chatId: Int64?
    public let chatName: String?
    public let chatType: Int?
    public let linkId: Int64?
    public let authorId: Int64?
    public let authorName: String?
    public let isFromMe: Bool?
    public let type: Int?
    public let text: String?
    public let attachment: String?
    public let sentAt: Int64?
    public let maxLogId: Int64?
    public let reason: String?

    public init(
        event: String, logId: Int64? = nil, chatId: Int64? = nil,
        chatName: String? = nil, chatType: Int? = nil, linkId: Int64? = nil,
        authorId: Int64? = nil, authorName: String? = nil, isFromMe: Bool? = nil,
        type: Int? = nil, text: String? = nil, attachment: String? = nil,
        sentAt: Int64? = nil, maxLogId: Int64? = nil, reason: String? = nil
    ) {
        self.event = event
        self.logId = logId
        self.chatId = chatId
        self.chatName = chatName
        self.chatType = chatType
        self.linkId = linkId
        self.authorId = authorId
        self.authorName = authorName
        self.isFromMe = isFromMe
        self.type = type
        self.text = text
        self.attachment = attachment
        self.sentAt = sentAt
        self.maxLogId = maxLogId
        self.reason = reason
    }

    public static func message(
        logId: Int64, chatId: Int64, chatName: String? = nil,
        chatType: Int, linkId: Int64, authorId: Int64, authorName: String? = nil,
        isFromMe: Bool, type: Int, text: String? = nil, attachment: String? = nil,
        sentAt: Int64
    ) -> KktEvent {
        KktEvent(
            event: KktConstants.messageEvent, logId: logId, chatId: chatId,
            chatName: chatName, chatType: chatType, linkId: linkId,
            authorId: authorId, authorName: authorName, isFromMe: isFromMe,
            type: type, text: text, attachment: attachment, sentAt: sentAt
        )
    }

    public static func scrap(logId: Int64, chatId: Int64, attachment: String) -> KktEvent {
        KktEvent(event: KktConstants.scrapEvent, logId: logId, chatId: chatId, attachment: attachment)
    }

    public static func heartbeat(maxLogId: Int64) -> KktEvent {
        KktEvent(event: KktConstants.heartbeatEvent, maxLogId: maxLogId)
    }

    public static func error(reason: String) -> KktEvent {
        KktEvent(event: KktConstants.errorEvent, reason: reason)
    }
}
