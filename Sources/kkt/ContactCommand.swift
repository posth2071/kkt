import ApplicationServices
import ArgumentParser
import Foundation
import KktCore

struct ContactCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: KktConstants.contactCommandName)

    @Option(name: .customLong(KktConstants.contactRoomOption))
    var roomChatId: Int64

    @Option(name: .customLong(KktConstants.contactUserOption))
    var userId: Int64

    @Option(name: .customLong(KktConstants.contactNicknameOption))
    var nickname: String

    @Flag(name: .customLong(KktConstants.sendDryRunOption))
    var dryRun = false

    func run() throws {
        let result: KktResult
        do {
            result = try ProgressIndicator.forTerminal().during(.handlingContact) {
                guard KakaoApp.runningPid() != nil else { throw KktError.kakaoNotRunning }
                try KakaoApp.checkNotInUse()
                let config = try KktConfig.load(environment: ProcessInfo.processInfo.environment)
                let lock = KktLock(path: config.lockPath)
                defer { lock.release() }
                try lock.acquire(timeout: KktConstants.lockDefaultTimeout)
                return try MainWindowKeeper().preserving { try execute(config: config) }
            }
        } catch {
            result = KktResult(result: KktConstants.failedResult, reason: ContactFlow.failureReason(error))
        }
        KktOutput.emit(result)
        if result.result == KktConstants.failedResult { throw ExitCode(KktConstants.failureExitCode) }
    }

    private func execute(config: KktConfig) throws -> KktResult {
        let reader = try KakaoDatabase.open(config: config)
        defer { reader.close() }
        let ui = ContactAXUI(room: {
            guard let room = try reader.room(chatId: roomChatId) else {
                throw KktError.notFound(String(roomChatId))
            }
            return room
        }, recognizeWindow: Self.recognize)
        return ContactFlow(ui: ui, lookupChatId: { try reader.directChatId(userId: $0) })
            .run(userId: userId, nickname: nickname, dryRun: dryRun)
    }

    private static func recognize(window: AXUIElement) throws -> [TextBox] {
        try ScreenText.recognize(window: window)
    }
}
