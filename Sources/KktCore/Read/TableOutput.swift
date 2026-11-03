import Foundation

public enum TableOutput {
    public static func render(columns: [String], rows: [[String]], truncate: Bool = true) -> String {
        guard !columns.isEmpty else { return KktConstants.emptyText }
        let cells = ([columns] + rows).map { row in
            columns.indices.map { clipped($0 < row.count ? row[$0] : KktConstants.emptyText, truncate: truncate) }
        }
        let widths = columns.indices.map { column in cells.map { width($0[column]) }.max() ?? KktConstants.zero }
        return cells.map { row in
            row.enumerated().map { column, cell in
                cell + (column == columns.count - KktConstants.one ? KktConstants.emptyText
                        : String(repeating: KktConstants.normalizedSpace, count: widths[column] - width(cell)))
            }.joined(separator: KktConstants.ReadTable.columnSeparator)
        }.joined(separator: KktConstants.newline)
    }

    public static func chats(_ chats: [ReadChat], timeZone: TimeZone = .current) -> String {
        render(columns: KktConstants.ReadTable.chatColumns, rows: chats.map {
            [String($0.id), $0.type, $0.displayName,
             $0.lastMessageAt.map { humanDate($0, timeZone: timeZone) } ?? KktConstants.emptyText, String($0.unreadCount)]
        })
    }

    public static func messages(_ messages: [ReadMessage], timeZone: TimeZone = .current) -> String {
        render(columns: KktConstants.ReadTable.messageColumns, rows: messages.map {
            [String($0.id), String($0.chatId), humanDate($0.timestamp, timeZone: timeZone),
             $0.isFromMe ? KktConstants.ReadTable.me : ($0.sender ?? KktConstants.Read.unknown),
             $0.text ?? $0.type]
        })
    }

    public static func candidates(_ chats: [ReadChat]) -> String {
        render(columns: KktConstants.ReadTable.candidateColumns,
               rows: chats.prefix(KktConstants.ReadNames.candidateLimit).map { [String($0.id), $0.displayName] })
    }

    public static func query(_ result: ReadQueryResult) -> String {
        render(columns: result.columns, rows: result.rows.map { $0.map(\.description) })
    }

    private static func humanDate(_ timestamp: String, timeZone: TimeZone) -> String {
        guard let date = ISO8601DateFormatter().date(from: timestamp) else { return timestamp }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: KktConstants.ReadTable.dateLocale)
        formatter.timeZone = timeZone
        formatter.dateFormat = KktConstants.ReadTable.dateFormat
        return formatter.string(from: date)
    }

    private static func clipped(_ value: String, truncate: Bool) -> String {
        var clean = value
        for (control, replacement) in KktConstants.ReadTable.escapes {
            clean = clean.replacingOccurrences(of: control, with: replacement)
        }
        clean = String(clean.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        guard truncate, width(clean) > KktConstants.ReadTable.maxCellWidth else { return clean }
        var result = KktConstants.emptyText
        for character in clean {
            guard width(result + String(character)) < KktConstants.ReadTable.maxCellWidth else { break }
            result.append(character)
        }
        return result + KktConstants.ReadTable.ellipsis
    }

    private static func width(_ value: String) -> Int {
        value.reduce(KktConstants.zero) { total, character in
            let wide = character.unicodeScalars.contains { scalar in
                KktConstants.ReadTable.wideRanges.contains { $0.contains(scalar.value) }
            }
            return total + (wide ? KktConstants.ReadTable.wideWidth : KktConstants.one)
        }
    }
}

extension KktConstants {
    enum ReadTable {
        static let dateLocale = "en_US_POSIX"
        static let dateFormat = "yyyy-MM-dd HH:mm"
        static let columnSeparator = "  "
        static let chatColumns = ["CHAT ID", "TYPE", "NAME", "UPDATED", "UNREAD"]
        static let messageColumns = ["LOG ID", "CHAT ID", "TIME", "SENDER", "TEXT"]
        static let candidateColumns = ["CHAT ID", "NAME"]
        static let me = "Me"
        static let maxCellWidth = 72
        static let ellipsis = "…"
        static let escapes = [("\n", "\\n"), ("\r", "\\r"), ("\t", "\\t")]
        static let wideWidth = 2
        static let wideRanges: [ClosedRange<UInt32>] = [
            0x1100...0x115F, 0x2329...0x232A, 0x2E80...0xA4CF, 0xAC00...0xD7A3,
            0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F, 0xFF01...0xFF60,
            0xFFE0...0xFFE6, 0x1F300...0x1FAFF, 0x20000...0x3FFFD,
        ]
    }
}
