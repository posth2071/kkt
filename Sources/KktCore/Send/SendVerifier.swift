import Foundation

public struct SentRow: Equatable {
    public let logId: Int64
    public let authorId: Int64
    public let message: String?

    public init(logId: Int64, authorId: Int64, message: String?) {
        self.logId = logId
        self.authorId = authorId
        self.message = message
    }
}

public struct SendVerifier {
    public enum Outcome: Equatable {
        case sent(logId: Int64)
        case uncertain
    }

    public static func match(rows: [SentRow], myUserId: Int64, startLogId: Int64, text: String) -> Int64? {
        let normalizedText = normalize(text)
        return rows.first { row in
            row.logId > startLogId && row.authorId == myUserId
                && (text.isEmpty || row.message.map(normalize) == normalizedText)
        }?.logId
    }

    public static func await(
        poll: TimeInterval, timeout: TimeInterval, myUserId: Int64, startLogId: Int64, text: String,
        fetch: () throws -> [SentRow], sleep: (TimeInterval) -> Void, clock: () -> Date
    ) throws -> Outcome {
        let deadline = clock().addingTimeInterval(timeout)
        while clock() < deadline {
            if let rows = try? fetch(),
               let logId = match(rows: rows, myUserId: myUserId, startLogId: startLogId, text: text) {
                return .sent(logId: logId)
            }
            let remaining = deadline.timeIntervalSince(clock())
            if remaining > KktConstants.zeroInterval { sleep(min(poll, remaining)) }
        }
        return .uncertain
    }

    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: KktConstants.normalizedSpace)
    }
}
