import ArgumentParser
import Foundation
import KktCore

struct NoticeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: KktConstants.Notice.command)

    @Option(name: .customLong(KktConstants.Read.chatIdOption))
    var chatId: Int64?

    @Option(name: .customLong(KktConstants.Read.chatOption))
    var chat: String?

    @Flag(name: .customLong(KktConstants.Read.jsonOption))
    var json = false

    func validate() throws {
        guard (chatId != nil) != (chat != nil), chat?.isEmpty != true else {
            throw ValidationError(KktConstants.Read.invalidTarget)
        }
    }

    func run() throws {
        do {
            let config = try KktConfig.load(environment: ProcessInfo.processInfo.environment)
            let database = try ReadQueries.retry { try KakaoDatabase.open(config: config) }
            defer { database.close() }
            let id: Int64
            if let chatId { id = chatId }
            else {
                guard let chat else { throw ValidationError(KktConstants.Read.invalidTarget) }
                let resolution = try ReadQueries.retry { try ReadQueries(database: database).resolveChat(named: chat) }
                guard let chatId = resolution.chatId else {
                    if json { KktOutput.emit(resolution.candidates) }
                    else { KktOutput.emitLine(TableOutput.candidates(resolution.candidates)) }
                    throw ExitCode(resolution.exitCode)
                }
                id = chatId
            }
            let reader = NoticeReader(fetch: { chatId in
                try ReadQueries.retry { try NoticeReader.databaseNotice(database: database, chatId: chatId) }
            }, screen: { chatId in
                let lock = KktLock(path: config.lockPath)
                try lock.acquire(timeout: KktConstants.lockDefaultTimeout)
                defer { lock.release() }
                let target = try ReadQueries.retry { try NoticeReader.screenTarget(database: database, chatId: chatId) }
                return try NoticeAX().read(target)
            })
            let result = try reader.read(chatId: id)
            if json { KktOutput.emit(result) }
            else { KktOutput.emitLine(result.humanReadable) }
        } catch let exit as ExitCode { throw exit }
        catch {
            KktOutput.emit(KktResult(result: KktConstants.failedResult,
                reason: (error as? KktError)?.code ?? KktError.databaseUnavailable.code))
            throw ExitCode(KktConstants.failureExitCode)
        }
    }
}
