import ArgumentParser
import Foundation
import KktCore

struct ServeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: KktConstants.serveCommandName)

    @Option(name: .customLong(KktConstants.serveSinceOption))
    var sinceLogId: Int64?

    @Option(name: .customLong(KktConstants.serveIntervalOption))
    var interval: Double = KktConstants.serveDefaultInterval

    mutating func run() throws {
        guard interval.isFinite, interval > .zero else {
            KktOutput.emit(ServeFailure(reason: KktConstants.invalidIntervalCode))
            throw ExitCode(KktConstants.failureExitCode)
        }
        let reader: KakaoDatabase
        let myUserId: Int64
        do {
            let config = try KktConfig.load(environment: ProcessInfo.processInfo.environment)
            reader = try KakaoDatabase.open(config: config)
            myUserId = try reader.myUserId()
        } catch {
            KktOutput.emit(ServeFailure(
                reason: (error as? KktError)?.code ?? KktConstants.databaseUnavailableCode
            ))
            throw ExitCode(KktConstants.failureExitCode)
        }
        defer { reader.close() }
        let loop = ServeLoop(
            fetch: { try reader.eventsAfter(logId: $0, limit: $1, myUserId: myUserId) },
            fetchAttachment: { try reader.scrapAttachment(chatId: $0, logId: $1) },
            maxLogId: { try reader.currentMaxLogId() }, emit: KktOutput.emitLine,
            sleep: { Thread.sleep(forTimeInterval: $0) }, clock: { Date() }, interval: interval
        )
        let status = loop.run(since: sinceLogId)
        if status != KktConstants.successExitCode { throw ExitCode(status) }
    }
}

private struct ServeFailure: Encodable {
    let result = KktConstants.failedResult
    let reason: String
}
