import Foundation

public protocol JoinUI {
    func openURL(_ url: URL) throws
    func newScreens() -> [JoinScreen]?
    func press(_ label: String) throws
    func setNickname(_ name: String) throws
    func closeNewWindows()
}

public enum JoinProfile {
    case kakao
    case nickname

    public init?(rawValue: String) {
        switch rawValue {
        case KktConstants.joinProfileKakao: self = .kakao
        case KktConstants.joinProfileNickname: self = .nickname
        default: return nil
        }
    }
}

public final class JoinFlow {
    private let ui: any JoinUI
    private let lookupChatId: (String) throws -> Int64?
    private let clock: () -> Date
    private let sleep: (TimeInterval) -> Void

    public init(ui: any JoinUI, lookupChatId: @escaping (String) throws -> Int64?,
                clock: @escaping () -> Date = { Date() },
                sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.ui = ui
        self.lookupChatId = lookupChatId
        self.clock = clock
        self.sleep = sleep
    }

    public func run(url: String, profile: JoinProfile = .kakao, nickname: String? = nil,
                    dryRun: Bool = false) -> KktResult {
        do {
            guard let target = JoinTarget.parse(url) else { throw KktError.invalidLink }
            if case .openLink(let code) = target, let chatId = try lookupChatId(code) {
                return KktResult(result: KktConstants.alreadyMemberResult, chatId: chatId)
            }
            if profile == .nickname,
               nickname?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw KktError.invalidNickname
            }
            defer { ui.closeNewWindows() }
            try ui.openURL(schemeURL(for: target))
            return try awaitScreen(target: target, profile: profile, nickname: nickname, dryRun: dryRun)
        } catch {
            return KktResult(result: KktConstants.failedResult,
                reason: (error as? KktError)?.code ?? KktConstants.automationCode)
        }
    }

    private func awaitScreen(target: JoinTarget, profile: JoinProfile, nickname: String?,
                             dryRun: Bool) throws -> KktResult {
        let deadline = clock().addingTimeInterval(KktConstants.joinScreenTimeout)
        var coverPressed = false
        var teamPressed = false
        while clock() < deadline {
            for screen in ui.newScreens() ?? [] {
                if let outcome = joinOutcome(screen: screen) { return KktResult(result: outcome) }
                switch screen {
                case .existingChat:
                    return try awaitChatId(target: target, result: KktConstants.alreadyMemberResult)
                case .cover(let joinButton):
                    if dryRun { return dryResult(KktConstants.joinCoverReason) }
                    if joinButton && !coverPressed {
                        try ui.press(KktConstants.joinButtonCover)
                        coverPressed = true
                    }
                case .profileChoice:
                    if dryRun { return dryResult(KktConstants.joinProfileReason) }
                    try confirmProfile(profile, nickname: nickname)
                    return try awaitChatId(target: target, result: KktConstants.joinedResult)
                case .teamRequest:
                    if dryRun { return dryResult(KktConstants.joinTeamReason) }
                    if !teamPressed {
                        try ui.press(KktConstants.teamRequestButton)
                        teamPressed = true
                    }
                case .message(let text):
                    if case .teamChat = target, text.contains(KktConstants.teamRequestedMarker) {
                        return KktResult(result: KktConstants.requestedResult)
                    }
                    throw KktError.automation(KktConstants.automationCode)
                case .passcode: return KktResult(result: KktConstants.needsPasswordResult)
                }
                break
            }
            sleep(KktConstants.windowPoll)
        }
        throw KktError.automation(KktConstants.automationCode)
    }

    private func confirmProfile(_ profile: JoinProfile, nickname: String?) throws {
        switch profile {
        case .kakao: try ui.press(KktConstants.joinKakaoProfileLabel)
        case .nickname:
            guard let nickname else { throw KktError.invalidNickname }
            try ui.setNickname(nickname)
        }
        try ui.press(KktConstants.joinButtonConfirm)
    }

    private func awaitChatId(target: JoinTarget, result: String) throws -> KktResult {
        guard case .openLink(let code) = target else { throw KktError.joinNotConfirmed }
        let deadline = clock().addingTimeInterval(KktConstants.joinDBTimeout)
        repeat {
            if let chatId = try lookupChatId(code) { return KktResult(result: result, chatId: chatId) }
            for screen in ui.newScreens() ?? [] {
                if let outcome = joinOutcome(screen: screen) { return KktResult(result: outcome) }
            }
            sleep(KktConstants.windowPoll)
        } while clock() < deadline
        throw KktError.joinNotConfirmed
    }

    private func dryResult(_ reason: String) -> KktResult {
        KktResult(result: KktConstants.dryRunResult, reason: reason)
    }
}
