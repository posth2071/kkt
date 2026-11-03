import AppKit
import ApplicationServices
import Foundation

public final class ChatOpener {
    struct Dependencies {
        var frontmostBundleId: () -> String? = KakaoApp.frontmostBundleId
        var runningPid: () -> pid_t? = KakaoApp.runningPid
        var appElement: (pid_t) -> AXUIElement = AXUIElementCreateApplication
        var windows: (AXUIElement) -> [AXUIElement] = AXHelpers.windows
        var identifier: (AXUIElement) -> String? = AXHelpers.identifier
        var title: (AXUIElement) -> String? = AXHelpers.title
        var captureFocus: () -> (() -> Void) = {
            let guard_ = FocusGuard()
            return { guard_.restore() }
        }
        var reopen: () throws -> Void = {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: KktConstants.restoreOpenPath)
            process.arguments = [KktConstants.mainWindowBackgroundArgument,
                                 KktConstants.restoreBundleArgument, KakaoApp.bundleId]
            guard (try? process.run()) != nil else { throw KktError.automation(KktConstants.automationCode) }
            process.waitUntilExit()
            guard process.terminationStatus == KktConstants.successExitCode else {
                throw KktError.automation(KktConstants.automationCode)
            }
        }
        var openURL: (URL) -> Void = ChatOpener.openURL
        var chatroomsTab: (AXUIElement) -> AXUIElement? = AXHelpers.chatroomsTab
        var press: (AXUIElement) -> Bool = { AXHelpers.performAction($0, kAXPressAction as String) }
        var search: (AXUIElement, pid_t) -> ChatSearch? = { ChatSearch(mainWindow: $0, pid: $1) }
        var table: (AXUIElement) -> AXUIElement? = AXHelpers.chatListTable
        var matchingRows: (AXUIElement, String, Bool) -> [AXUIElement] = AXHelpers.matchingChatRows
        var selectRow: (AXUIElement, AXUIElement) -> Bool = { AXHelpers.selectRow($0, in: $1) }
        var focus: (AXUIElement) -> Bool = AXHelpers.focus
        var pressReturn: (pid_t) -> Void = BackgroundInput.pressReturn
        var clock: () -> Date = { Date() }
        var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    }

    private let dependencies: Dependencies

    public convenience init() { self.init(dependencies: Dependencies()) }

    init(dependencies: Dependencies) { self.dependencies = dependencies }

    public func open(_ target: SendTarget) throws -> AXUIElement {
        try KakaoApp.checkNotInUse(frontmostBundleId: dependencies.frontmostBundleId)
        guard let pid = dependencies.runningPid() else { throw KktError.kakaoNotRunning }
        let restoreFocus = dependencies.captureFocus()
        defer { restoreFocus() }
        let (app, mainWindow) = try prepareWindows(pid: pid, restoreFocus: restoreFocus)
        switch target {
        case .openLink(let code, let title):
            do {
                return try openChat(app: app, mainWindow: mainWindow, pid: pid, name: title, selfChat: false)
            } catch KktError.notFound {
                return try openLink(app: app, code: code, title: title, restoreFocus: restoreFocus)
            }
        case .selfChat(let name):
            return try openChat(app: app, mainWindow: mainWindow, pid: pid,
                                name: name, selfChat: true)
        case .direct(let name), .group(let name):
            return try openChat(app: app, mainWindow: mainWindow, pid: pid, name: name, selfChat: false)
        }
    }

    public static func prepareWindows(frontmostBundleId: @escaping () -> String? = KakaoApp.frontmostBundleId) throws
        -> (app: AXUIElement, mainWindow: AXUIElement) {
        var dependencies = Dependencies()
        dependencies.frontmostBundleId = frontmostBundleId
        return try prepareWindows(dependencies: dependencies)
    }

    static func prepareWindows(dependencies: Dependencies) throws
        -> (app: AXUIElement, mainWindow: AXUIElement) {
        try KakaoApp.checkNotInUse(frontmostBundleId: dependencies.frontmostBundleId)
        guard let pid = dependencies.runningPid() else { throw KktError.kakaoNotRunning }
        var restoreFocus: (() -> Void)?
        defer { restoreFocus?() }
        let restore: () -> Void = {
            restoreFocus?()
        }
        var preparation = dependencies
        preparation.reopen = {
            restoreFocus = dependencies.captureFocus()
            try dependencies.reopen()
        }
        let preparedOpener = ChatOpener(dependencies: preparation)
        return try preparedOpener.prepareWindows(pid: pid, restoreFocus: restore)
    }

    private func prepareWindows(pid: pid_t, restoreFocus: () -> Void) throws
        -> (app: AXUIElement, mainWindow: AXUIElement) {
        let app = dependencies.appElement(pid)
        let (mainWindow, windows) = try MainWindowReopener.find(
            windows: { dependencies.windows(app) },
            isMainWindow: { dependencies.identifier($0) == KktConstants.mainWindowIdentifier },
            reopen: dependencies.reopen, sleep: dependencies.sleep, clock: dependencies.clock,
            restoreFocus: restoreFocus)
        try checkWindows(windows)
        return (app, mainWindow)
    }

    private func checkWindows(_ windows: [AXUIElement]) throws {
        try UserWindowGuard.check(windows: windows.map {
            WindowInfo(identifier: dependencies.identifier($0), title: dependencies.title($0))
        })
    }

    public static func openURL(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration)
    }

    private func openLink(app: AXUIElement, code: String, title: String,
                          restoreFocus: () -> Void) throws -> AXUIElement {
        let previousWindows = dependencies.windows(app)
        try checkWindows(previousWindows)
        guard let url = URL(string: String(format: KktConstants.kakaoopenJoinFormat, code)) else {
            throw KktError.automation(KktConstants.automationCode)
        }
        dependencies.openURL(url)
        let deadline = dependencies.clock().addingTimeInterval(KktConstants.openWindowTimeout)
        while dependencies.clock() < deadline {
            let windows = newWindows(in: app, excluding: previousWindows)
            switch Self.pickOpenedWindow(titles: windows.map(dependencies.title), expected: title) {
            case .found(let index):
                restoreFocus()
                return windows[index]
            case .unexpected:
                throw KktError.automation(KktConstants.unexpectedWindow)
            case .waiting:
                dependencies.sleep(KktConstants.windowPoll)
            }
        }
        throw KktError.automation(KktConstants.automationCode)
    }

    private func openChat(app: AXUIElement, mainWindow: AXUIElement, pid: pid_t,
                          name: String, selfChat: Bool) throws -> AXUIElement {
        if let tab = dependencies.chatroomsTab(mainWindow) {
            guard dependencies.press(tab) else { throw KktError.automation(KktConstants.automationCode) }
            dependencies.sleep(KktConstants.actionSettle)
        }
        var search: ChatSearch?
        defer { search?.restore() }
        let match: (table: AXUIElement, row: AXUIElement)?
        if let visibleMatch = matchingChatRow(in: mainWindow, name: name, selfChat: selfChat) {
            match = visibleMatch
        } else {
            search = dependencies.search(mainWindow, pid)
            match = findChatRow(in: mainWindow, search: search, name: name, selfChat: selfChat)
        }
        guard let (table, row) = match else {
            throw KktError.notFound(name)
        }
        let previousWindows = dependencies.windows(app)
        try checkWindows(previousWindows)
        guard dependencies.selectRow(row, table) else { throw KktError.notFound(name) }
        dependencies.sleep(KktConstants.selectionSettle)
        guard dependencies.focus(table) else { throw KktError.automation(KktConstants.automationCode) }
        dependencies.pressReturn(pid)
        let deadline = dependencies.clock().addingTimeInterval(KktConstants.openWindowTimeout)
        while dependencies.clock() < deadline {
            let windows = newWindows(in: app, excluding: previousWindows)
            if selfChat {
                if let window = windows.first(where: { !(dependencies.title($0) ?? KktConstants.emptyText).isEmpty }) {
                    return window
                }
            } else {
                switch Self.pickOpenedWindow(titles: windows.map(dependencies.title), expected: name) {
                case .found(let index): return windows[index]
                case .unexpected: throw KktError.notFound(name)
                case .waiting: break
                }
            }
            dependencies.sleep(KktConstants.windowPoll)
        }
        throw KktError.automation(KktConstants.automationCode)
    }

    private func findChatRow(in mainWindow: AXUIElement, search: ChatSearch?, name: String,
                             selfChat: Bool) -> (table: AXUIElement, row: AXUIElement)? {
        guard let search, search.clear() else { return nil }
        if let match = awaitRow(in: mainWindow, name: name, selfChat: selfChat, timeout: KktConstants.searchClearTimeout) {
            return match
        }
        guard !name.isEmpty else { return nil }
        search.type(name)
        return awaitRow(in: mainWindow, name: name, selfChat: selfChat, timeout: KktConstants.searchFilterTimeout)
    }

    private func awaitRow(in mainWindow: AXUIElement, name: String, selfChat: Bool,
                          timeout: TimeInterval) -> (table: AXUIElement, row: AXUIElement)? {
        let deadline = dependencies.clock().addingTimeInterval(timeout)
        repeat {
            if let match = matchingChatRow(in: mainWindow, name: name, selfChat: selfChat) { return match }
            dependencies.sleep(KktConstants.searchClearPoll)
        } while dependencies.clock() < deadline
        return nil
    }

    private func matchingChatRow(in mainWindow: AXUIElement, name: String,
                                 selfChat: Bool) -> (table: AXUIElement, row: AXUIElement)? {
        guard let table = dependencies.table(mainWindow) else { return nil }
        return Self.uniqueMatch(dependencies.matchingRows(table, name, selfChat)).map { (table, $0) }
    }

    public static func uniqueMatch<T>(_ matches: [T]) -> T? {
        matches.count == KktConstants.uniqueMatchCount ? matches.first : nil
    }

    public enum WindowPick: Equatable { case found(Int), unexpected, waiting }

    public static func pickOpenedWindow(titles: [String?], expected: String) -> WindowPick {
        let titled = titles.enumerated().compactMap { item -> (Int, String)? in
            guard let title = item.element, !title.isEmpty else { return nil }
            return (item.offset, title)
        }
        if let match = titled.first(where: { $0.1 == expected }) { return .found(match.0) }
        return titled.isEmpty ? .waiting : .unexpected
    }

    private func newWindows(in app: AXUIElement, excluding previousWindows: [AXUIElement]) -> [AXUIElement] {
        dependencies.windows(app).filter { window in
            dependencies.identifier(window) != KktConstants.mainWindowIdentifier
                && !previousWindows.contains(where: { CFEqual($0, window) })
        }
    }
}

