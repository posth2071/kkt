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

    @Option(name: .customLong(KktConstants.sendViaCardRoomOption))
    var viaCardRoom: Int64?

    @Option(name: .customLong(KktConstants.sendViaCardUserOption))
    var viaCardUser: Int64?

    @Option(name: .customLong(KktConstants.sendViaCardNicknameOption))
    var viaCardNickname: String?

    private var cardRoute: CardRoute? {
        guard let viaCardRoom, let viaCardUser, let viaCardNickname else { return nil }
        return CardRoute(roomChatId: viaCardRoom, userId: viaCardUser, nickname: viaCardNickname)
    }

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
            KktOutput.emit(try MainWindowKeeper().preserving {
                try operation.execute(chatId: chatId, text: text, images: images, dryRun: dryRun, viaCard: cardRoute)
            })
        } catch {
            KktOutput.emit(KktResult(result: KktConstants.failedResult,
                reason: cardRoute == nil ? (error as? KktError)?.code ?? KktConstants.automationCode
                    : ContactFlow.failureReason(error)))
            throw ExitCode(KktConstants.failureExitCode)
        }
    }
}
