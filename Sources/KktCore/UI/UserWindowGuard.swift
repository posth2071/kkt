public struct WindowInfo: Equatable, Sendable {
    public let identifier: String?
    public let title: String?

    public init(identifier: String?, title: String?) {
        self.identifier = identifier
        self.title = title
    }
}

public enum UserWindowGuard {
    public static func check(windows: [WindowInfo]) throws {
        guard windows.allSatisfy({ $0.identifier == KktConstants.mainWindowIdentifier }) else {
            throw KktError.chatWindowOpen
        }
    }
}
