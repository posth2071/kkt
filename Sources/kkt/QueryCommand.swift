import ArgumentParser
import Foundation
import KktCore

struct QueryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: KktConstants.Read.queryCommand)

    @Argument
    var sql: String

    @Flag(name: .customLong(KktConstants.Read.jsonOption))
    var json = false

    func run() throws {
        do { try ReadOnlySQL.validate(sql) }
        catch { try failReadCommand(error) }
        let result = try withReadDatabase { try $0.query(sql) }
        if json { KktOutput.emit(result.rows) }
        else { KktOutput.emitLine(TableOutput.query(result)) }
    }
}

func withReadDatabase<T>(_ operation: (ReadQueries) throws -> T) throws -> T {
    do {
        let config = try KktConfig.load(environment: ProcessInfo.processInfo.environment)
        return try ReadQueries.retry {
            let database = try KakaoDatabase.open(config: config)
            defer { database.close() }
            return try operation(ReadQueries(database: database))
        }
    } catch { try failReadCommand(error) }
}

private func failReadCommand(_ error: Error) throws -> Never {
    KktOutput.emit(KktResult(result: KktConstants.failedResult,
                             reason: (error as? KktError)?.code ?? KktConstants.databaseUnavailableCode))
    throw ExitCode(KktConstants.failureExitCode)
}

func validateReadOptions(since: String?, limit: Int) throws {
    guard limit > .zero else { throw ValidationError(KktConstants.Read.invalidLimit) }
    if let since, ReadQueries.parseSince(since) == nil {
        throw ValidationError(KktConstants.Read.invalidSince)
    }
}
