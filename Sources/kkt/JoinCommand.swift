import ArgumentParser
import Foundation
import KktCore

struct JoinCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: KktConstants.joinCommandName)

    @Argument var url: String

    @Option(name: .customLong(KktConstants.joinProfileOption))
    var profile: String = KktConstants.joinProfileKakao

    @Option(name: .customLong(KktConstants.joinNicknameOption))
    var nickname: String?

    @Flag(name: .customLong(KktConstants.sendDryRunOption))
    var dryRun = false

    func run() throws {
        let result: KktResult
        do {
            guard KakaoApp.runningPid() != nil else { throw KktError.kakaoNotRunning }
            try KakaoApp.checkNotInUse()
            let config = try KktConfig.load(environment: ProcessInfo.processInfo.environment)
            let lock = KktLock(path: config.lockPath)
            defer { lock.release() }
            try lock.acquire(timeout: KktConstants.lockDefaultTimeout)
            result = try execute(config: config)
        } catch {
            result = KktResult(result: KktConstants.failedResult,
                reason: (error as? KktError)?.code ?? KktConstants.automationCode)
        }
        KktOutput.emit(result)
        if result.result == KktConstants.failedResult { throw ExitCode(KktConstants.failureExitCode) }
    }

    private func execute(config: KktConfig) throws -> KktResult {
        guard let target = JoinTarget.parse(url) else { throw KktError.invalidLink }
        guard let profile = JoinProfile(rawValue: profile) else { throw KktError.invalidProfile }
        var reader: KakaoDatabase?
        defer { reader?.close() }
        func database() throws -> KakaoDatabase {
            if let reader { return reader }
            let opened = try KakaoDatabase.open(config: config)
            reader = opened
            return opened
        }
        let ui = JoinAXUI(knownChatTitles: {
            if case .teamChat = target { return [] }
            return try database().knownJoinChatTitles()
        })
        let flow = JoinFlow(ui: ui, lookupChatId: { try database().joinedChatId(code: $0) })
        return flow.run(url: url, profile: profile, nickname: nickname, dryRun: dryRun)
    }
}
