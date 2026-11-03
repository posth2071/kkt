public enum KktError: Error, Equatable, CustomStringConvertible {
    case busy
    case notFound(String)
    case ambiguous(String)
    case automation(String)
    case inputLocked
    case invalidLink
    case invalidProfile
    case invalidNickname
    case joinNotConfirmed
    case chatWindowOpen
    case kakaoNotRunning
    case kakaoInUse
    case readOnlySQL
    case databaseUnavailable
    case invalidConfig

    public var code: String {
        switch self {
        case .busy: KktConstants.Code.busy
        case .notFound: KktConstants.Code.notFound
        case .ambiguous: KktConstants.Code.ambiguous
        case .automation: KktConstants.Code.automation
        case .inputLocked: KktConstants.Code.inputLocked
        case .invalidLink: KktConstants.Code.invalidLink
        case .invalidProfile: KktConstants.Code.invalidProfile
        case .invalidNickname: KktConstants.Code.invalidNickname
        case .joinNotConfirmed: KktConstants.Code.joinNotConfirmed
        case .chatWindowOpen: KktConstants.Code.chatWindowOpen
        case .kakaoNotRunning: KktConstants.Code.kakaoNotRunning
        case .kakaoInUse: KktConstants.Code.kakaoInUse
        case .readOnlySQL: KktConstants.Code.readOnlySQL
        case .databaseUnavailable: KktConstants.Code.databaseUnavailable
        case .invalidConfig: KktConstants.Code.invalidConfig
        }
    }

    public var description: String { code }
}
