import ArgumentParser
import Foundation
import KktCore

struct SendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: KktConstants.sendCommandName)

    @Option(name: .customLong(KktConstants.sendChatIdOption))
    var chatId: Int64

    @Option(name: .customLong(KktConstants.sendTextOption))
    var text: String = String()

    @Option(name: .customLong(KktConstants.sendImageOption), parsing: .upToNextOption)
    var images: [String] = []

    @Flag(name: .customLong(KktConstants.sendDryRunOption))
    var dryRun = false

    func run() throws {
        do {
            guard KakaoApp.runningPid() != nil else { throw KktError.kakaoNotRunning }
            let config = try KktConfig.load(environment: ProcessInfo.processInfo.environment)
            let lock = KktLock(path: config.lockPath)
            defer { lock.release() }
            try lock.acquire(timeout: KktConstants.lockDefaultTimeout)
            let reader = try KakaoDatabase.open(config: config)
            defer { reader.close() }
            let operation = SendOperation(reader: reader, interval: SendInterval(path: config.lockPath))
            KktOutput.emit(try operation.execute(chatId: chatId, text: text, images: images, dryRun: dryRun))
        } catch {
            KktOutput.emit(KktResult(result: KktConstants.failedResult,
                reason: (error as? KktError)?.code ?? KktConstants.automationCode))
            throw ExitCode(KktConstants.failureExitCode)
        }
    }
}
