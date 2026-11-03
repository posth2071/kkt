import Foundation

public enum RoomNames {
    public static let displayNameExpression = KktConstants.ReadNames.expression

    public static func memberName(hex: String?, memberCount: Int, users: [Int64: String]) -> String? {
        guard let hex, hex.count.isMultiple(of: KktConstants.ReadNames.hexPairLength) else { return nil }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: KktConstants.ReadNames.hexPairLength)
            guard let byte = UInt8(hex[index..<next], radix: KktConstants.hexRadix) else { return nil }
            data.append(byte)
            index = next
        }
        guard let ids = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [NSNumber] else {
            return nil
        }
        let names = ids.compactMap { users[$0.int64Value] }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(KktConstants.ReadNames.maxMemberNames)
        var name = shown.joined(separator: KktConstants.ReadNames.memberSeparator)
        let extra = max(memberCount, names.count) - shown.count - KktConstants.one
        if extra > KktConstants.zero {
            name += KktConstants.ReadNames.extraPrefix + String(extra) + KktConstants.ReadNames.extraSuffix
        }
        return name
    }
}

extension KktConstants {
    enum ReadNames {
        static let expression = """
            COALESCE(NULLIF(r.chatName,''), NULLIF(meta3.groupNickname,''), NULLIF(ol.linkName,''),
                     NULLIF(du.friendNickName,''), NULLIF(du.displayName,''), NULLIF(du.nickName,''))
            """
        static let usersQuery = """
            SELECT userId, COALESCE(NULLIF(friendNickName,''), NULLIF(displayName,''), NULLIF(nickName,''))
            FROM NTUser ORDER BY linkId
            """
        static let maxMemberNames = 4
        static let hexPairLength = 2
        static let memberSeparator = ", "
        static let extraPrefix = " 외 "
        static let extraSuffix = "명"
        static let unknown = "(unknown)"
        static let allRoomsLimit = -1
        static let candidateLimit = 20
    }
}
