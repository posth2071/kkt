import Foundation

public enum JoinTarget: Equatable {
    case openLink(code: String)
    case teamChat(token: String)

    public static func parse(_ raw: String) -> JoinTarget? {
        let input = raw.contains(KktConstants.joinSchemeSeparator) ? raw : KktConstants.joinDefaultPrefix + raw
        guard let url = URLComponents(string: input),
              [KktConstants.joinHTTP, KktConstants.joinHTTPS].contains(url.scheme?.lowercased()),
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        let path = url.path.split(separator: KktConstants.joinPathSeparator)
        guard path.count == KktConstants.joinPathCount else { return nil }
        let kind = String(path[KktConstants.joinPathKindIndex])
        let code = String(path[KktConstants.joinPathCodeIndex])
        guard code.range(of: KktConstants.joinCodePattern, options: .regularExpression) != nil else { return nil }
        switch (url.host?.lowercased(), kind) {
        case (KktConstants.joinOpenHost, KktConstants.joinOpenPath): return .openLink(code: code)
        case (KktConstants.joinTeamHost, KktConstants.joinTeamPath): return .teamChat(token: code)
        default: return nil
        }
    }
}

public func schemeURL(for target: JoinTarget) -> URL {
    var components = URLComponents()
    switch target {
    case .openLink(let code):
        components.scheme = KktConstants.joinOpenScheme
        components.host = KktConstants.joinSchemeHost
        components.queryItems = [URLQueryItem(name: KktConstants.joinCodeParameter, value: code)]
    case .teamChat(let token):
        components.scheme = KktConstants.joinTeamScheme
        components.host = KktConstants.joinTeamSchemeHost
        components.path = KktConstants.joinTeamSchemePath
        components.queryItems = [URLQueryItem(name: KktConstants.joinTokenParameter, value: token)]
    }
    return components.url!
}

public enum JoinScreen: Equatable {
    case existingChat(title: String)
    case cover(joinButton: Bool)
    case profileChoice
    case passcode
    case teamRequest
    case message(String)
}

public func classifyJoinScreen(windowTitles: [String], buttonTitles: [String], texts: [String],
                               knownChatTitles: Set<String>) -> JoinScreen? {
    if let title = windowTitles.first(where: knownChatTitles.contains) { return .existingChat(title: title) }
    let content = (windowTitles + texts).joined(separator: KktConstants.newline)
    if KktConstants.joinPasscodeMarkers.contains(where: content.contains) { return .passcode }
    if content.contains(KktConstants.teamRequestedMarker) { return .message(content) }
    if joinOutcome(screen: .message(content)) != nil { return .message(content) }
    if buttonTitles.contains(KktConstants.teamRequestButton) { return .teamRequest }
    if texts.contains(where: { $0.contains(KktConstants.joinNicknamePlaceholder) })
        || buttonTitles.contains(KktConstants.joinButtonConfirm) { return .profileChoice }
    if buttonTitles.contains(KktConstants.joinButtonCover) { return .cover(joinButton: true) }
    if texts.contains(KktConstants.joinButtonCover) { return .cover(joinButton: false) }
    return content.isEmpty ? nil : .message(content)
}

public func joinOutcome(screen: JoinScreen) -> String? {
    switch screen {
    case .passcode: return KktConstants.needsPasswordResult
    case .message(let text):
        if KktConstants.joinFullMarkers.allSatisfy(text.contains) { return KktConstants.fullResult }
        if KktConstants.joinEndedMarkers.contains(where: text.contains) { return KktConstants.endedResult }
        if KktConstants.joinIneligibleMarkers.contains(where: text.contains) { return KktConstants.ineligibleResult }
        return nil
    default: return nil
    }
}
