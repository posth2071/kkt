import CSQLCipher
import Foundation

public enum SQLValue {
    case int(Int)
    case int64(Int64)
    case double(Double)
    case string(String)
    case null
}

public struct Row {
    let statement: OpaquePointer

    public func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
    public func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    public func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    public func optionalInt64(_ column: Int32) -> Int64? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : int64(column)
    }
    public func string(_ column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        return String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)
    }
    public func bool(_ column: Int32) -> Bool { int64(column) != KktConstants.zero }
    public func kakaoDate(_ column: Int32) -> Date { Date(timeIntervalSince1970: double(column)) }
    public func optionalKakaoDate(_ column: Int32) -> Date? {
        guard let value = optionalInt64(column), value != KktConstants.zero else { return nil }
        return Date(timeIntervalSince1970: Double(value))
    }
}

public final class KakaoDatabase {
    private var database: OpaquePointer?
    public let databasePath: String

    private init(databasePath: String, database: OpaquePointer) {
        self.databasePath = databasePath
        self.database = database
    }

    deinit { close() }

    public static func open(
        config: KktConfig,
        uuid: () throws -> String = { try DeviceInfo.platformUUID() },
        containerPath: String = DeviceInfo.containerPath
    ) throws -> KakaoDatabase {
        guard let userId = config.userId else { throw KktError.notFound(KktConstants.Device.accountResource) }
        let deviceUUID = try uuid()
        let name = KeyDerivation.databaseName(userId: userId, uuid: deviceUUID)
        let base = URL(fileURLWithPath: containerPath).appendingPathComponent(name).path
        let candidates = [base, base + KktConstants.Database.fileExtension]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
                ?? DeviceInfo.discoverDatabaseFile(in: containerPath) else {
            throw KktError.notFound(KktConstants.Database.resource)
        }
        return try open(databasePath: path, key: KeyDerivation.secureKey(userId: userId, uuid: deviceUUID))
    }

    public static func open(
        databasePath: String, key: String? = nil,
        compatModes: [Int] = KktConstants.compatModesNewestFirst
    ) throws -> KakaoDatabase {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw KktError.notFound(KktConstants.Database.resource)
        }
        for compatibility in key == nil ? [KktConstants.zero] : compatModes {
            var handle: OpaquePointer?
            let status = sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
            guard status == SQLITE_OK, let handle else {
                if let handle { sqlite3_close(handle) }
                throw KktError.databaseUnavailable
            }
            let reader = KakaoDatabase(databasePath: databasePath, database: handle)
            do {
                if let key {
                    try reader.execute(KktConstants.Database.compatibilityPragma + String(compatibility))
                    try reader.execute(KktConstants.Database.keyPragma
                                       + key.replacingOccurrences(of: KktConstants.Database.quote,
                                                                  with: KktConstants.Database.quote + KktConstants.Database.quote)
                                       + KktConstants.Database.quote)
                }
                _ = try reader.query(KktConstants.Database.validationQuery, bind: []) { $0.int(KktConstants.zeroColumn) }
                return reader
            } catch {
                reader.close()
                if error as? KktError == .busy { throw KktError.busy }
            }
        }
        throw KktError.databaseUnavailable
    }

    public func close() {
        if let database { sqlite3_close(database) }
        database = nil
    }

    public func query<T>(_ sql: String, bind: [SQLValue], row: (Row) -> T) throws -> [T] {
        guard let database else { throw KktError.databaseUnavailable }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, KktConstants.Database.nullTerminated, &statement, nil)
        if status == SQLITE_BUSY || status == SQLITE_LOCKED { throw KktError.busy }
        guard status == SQLITE_OK,
              let statement else { throw KktError.databaseUnavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_stmt_readonly(statement) != KktConstants.zero else { throw KktError.readOnlySQL }
        for (offset, value) in bind.enumerated() {
            let index = Int32(offset + KktConstants.one)
            let result: Int32
            switch value {
            case .int(let value): result = sqlite3_bind_int64(statement, index, Int64(value))
            case .int64(let value): result = sqlite3_bind_int64(statement, index, value)
            case .double(let value): result = sqlite3_bind_double(statement, index, value)
            case .string(let value):
                result = value.withCString {
                    sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count),
                                      unsafeBitCast(Int(KktConstants.Database.nullTerminated), to: sqlite3_destructor_type.self))
                }
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw KktError.databaseUnavailable }
        }
        var rows: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: rows.append(row(Row(statement: statement)))
            case SQLITE_DONE: return rows
            case SQLITE_BUSY, SQLITE_LOCKED: throw KktError.busy
            default: throw KktError.databaseUnavailable
            }
        }
    }

    public func room(chatId: Int64) throws -> RoomRow? {
        typealias Column = KktConstants.RoomColumn
        let rooms = try query(KktConstants.roomQuery, bind: [.int64(chatId)]) { row in
            RoomRow(chatId: row.int64(Column.chatId), type: row.int(Column.type),
                    linkId: row.int64(Column.linkId), linkUrl: row.string(Column.linkUrl),
                    displayName: row.string(Column.displayName) ?? KktConstants.emptyText)
        }
        return rooms.first
    }

    public func sameNameCount(displayName: String) throws -> Int {
        let counts = try query(KktConstants.sameNameCountQuery, bind: [
            .string(displayName),
            .string(displayName.precomposedStringWithCanonicalMapping),
            .string(displayName.decomposedStringWithCanonicalMapping),
        ]) { row in
            row.int(KktConstants.countColumn)
        }
        return counts.first ?? KktConstants.noMatchingNames
    }

    public func sentRows(chatId: Int64, after logId: Int64) throws -> [SentRow] {
        typealias Column = KktConstants.SentColumn
        let rows = try query(KktConstants.sentRowsQuery, bind: [
            .int64(chatId), .int64(logId), .int64(KktConstants.pendingLogIdSentinel),
        ]) { row in
            SentRow(logId: row.int64(Column.logId), authorId: row.int64(Column.authorId),
                    message: row.string(Column.message))
        }
        return rows
    }


    public func directChatId(userId: Int64) throws -> Int64? {
        try query(KktConstants.contactDirectQuery, bind: [.int64(userId)]) {
            $0.int64(KktConstants.contactFirstColumn)
        }.first
    }

    public func joinedChatId(code: String) throws -> Int64? {
        try query(KktConstants.joinChatIdQuery, bind: [.string(code)]) {
            $0.int64(KktConstants.joinFirstColumn)
        }.first
    }

    public func knownJoinChatTitles() throws -> Set<String> {
        let rows = try query(KktConstants.joinKnownTitlesQuery, bind: []) {
            $0.string(KktConstants.joinFirstColumn)
        }
        return Set(rows.compactMap { $0 }.filter { !$0.isEmpty })
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw KktError.databaseUnavailable }
    }
}
