import Foundation

public struct RoomRow: Equatable {
    public let chatId: Int64
    public let type: Int
    public let linkId: Int64
    public let linkUrl: String?
    public let displayName: String

    public init(chatId: Int64, type: Int, linkId: Int64, linkUrl: String?, displayName: String) {
        self.chatId = chatId
        self.type = type
        self.linkId = linkId
        self.linkUrl = linkUrl
        self.displayName = displayName
    }

    public var needsNameLookup: Bool {
        type != KktConstants.selfRoomType && openLinkCode == nil
    }

    var openLinkCode: String? {
        guard linkId != KktConstants.noLinkId, let linkUrl,
              let code = URL(string: linkUrl)?.lastPathComponent, !code.isEmpty else { return nil }
        return code
    }
}

public enum SendTarget: Equatable {
    case openLink(code: String, title: String)
    case direct(name: String)
    case group(name: String)
    case selfChat(name: String)
}

public struct CardRoute: Equatable {
    public let roomChatId: Int64
    public let userId: Int64
    public let nickname: String

    public init(roomChatId: Int64, userId: Int64, nickname: String) {
        self.roomChatId = roomChatId
        self.userId = userId
        self.nickname = nickname
    }
}

public func resolveTarget(chatId: Int64, room: RoomRow, sameNameCount: Int) throws -> SendTarget {
    guard room.chatId == chatId else { throw KktError.notFound(String(chatId)) }
    if room.type == KktConstants.selfRoomType { return .selfChat(name: room.displayName) }
    if let code = room.openLinkCode { return .openLink(code: code, title: room.displayName) }
    if sameNameCount > KktConstants.uniqueNameCount { throw KktError.ambiguous(room.displayName) }
    guard !room.displayName.isEmpty else { throw KktError.notFound(String(chatId)) }
    return room.type == KktConstants.directRoomType
        ? .direct(name: room.displayName) : .group(name: room.displayName)
}

public enum InputState: Equatable {
    case ready, locked, missing
}

public func classifyInput(windowTexts: [String], hasField: Bool) -> InputState {
    if hasField { return .ready }
    return windowTexts.contains { $0.contains(KktConstants.lockedInputMarker) } ? .locked : .missing
}
