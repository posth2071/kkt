import Foundation

public struct KktResult: Encodable, Equatable {
    public let result: String
    public let reason: String?
    public let chatId: Int64?
    public let logId: Int64?
    public let friendAdded: Bool?
    public let dryRun: Bool?
    public let imageRoute: String?

    public init(
        result: String,
        reason: String? = nil,
        chatId: Int64? = nil,
        logId: Int64? = nil,
        friendAdded: Bool? = nil,
        dryRun: Bool? = nil,
        imageRoute: String? = nil
    ) {
        self.result = result
        self.reason = reason
        self.chatId = chatId
        self.logId = logId
        self.friendAdded = friendAdded
        self.dryRun = dryRun
        self.imageRoute = imageRoute
    }
}

public enum KktOutput {
    public static func line<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        } catch {
            return KktConstants.encodeFailure
        }
    }

    public static func emit<T: Encodable>(_ value: T) {
        emitLine(line(value))
    }

    public static func emitLine(_ line: String) {
        FileHandle.standardOutput.write(Data((line + KktConstants.newline).utf8))
    }
}
