import ApplicationServices

public struct MainWindowKeeper {
    enum State {
        case open
        case minimized
        case closed
    }

    struct Dependencies {
        var runningPid: () -> pid_t? = KakaoApp.runningPid
        var appElement: (pid_t) -> AXUIElement = AXUIElementCreateApplication
        var windows: (AXUIElement) -> [AXUIElement]? = { AXHelpers.elements($0, attribute: kAXWindowsAttribute as String) }
        var identifier: (AXUIElement) -> String? = AXHelpers.identifier
        var isMinimized: (AXUIElement) -> Bool = AXHelpers.isMinimized
        var close: (AXUIElement) -> Void = { _ = AXHelpers.closeWindow($0) }
        var minimize: (AXUIElement) -> Void = { _ = AXHelpers.minimize($0) }
    }

    private let dependencies: Dependencies

    public init() { dependencies = Dependencies() }
    init(dependencies: Dependencies) { self.dependencies = dependencies }

    public func preserving<Result>(_ work: () throws -> Result) rethrows -> Result {
        let before = state()
        defer { restore(before) }
        return try work()
    }

    private func readWindows() -> [AXUIElement]? {
        dependencies.runningPid().flatMap { dependencies.windows(dependencies.appElement($0)) }
    }

    private func mainWindow(in windows: [AXUIElement]) -> AXUIElement? {
        windows.first { dependencies.identifier($0) == KktConstants.mainWindowIdentifier }
    }

    private func state() -> State? {
        guard let windows = readWindows() else { return nil }
        guard let window = mainWindow(in: windows) else { return .closed }
        return dependencies.isMinimized(window) ? .minimized : .open
    }

    private func restore(_ before: State?) {
        guard before == .closed || before == .minimized, let windows = readWindows(),
              let window = mainWindow(in: windows), !dependencies.isMinimized(window) else { return }
        if before == .closed { dependencies.close(window) } else { dependencies.minimize(window) }
    }
}
