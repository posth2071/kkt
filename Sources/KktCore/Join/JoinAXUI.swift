import AppKit
import ApplicationServices
import Foundation

public enum JoinScreenReader {
    public static func snapshot(window: AXUIElement) -> (titles: [String], buttons: [String], texts: [String]) {
        var buttons: [String] = []
        var texts: [String] = []
        for element in elements(in: window) {
            let role = AXHelpers.role(element)
            if role == kAXButtonRole as String, let title = AXHelpers.title(element), !title.isEmpty {
                buttons.append(title)
            }
            if role == kAXStaticTextRole as String {
                texts += [AXHelpers.title(element), AXHelpers.value(element)].compactMap { $0 }.filter { !$0.isEmpty }
            }
            if let placeholder = AXHelpers.attribute(element, kAXPlaceholderValueAttribute as String),
               !placeholder.isEmpty { texts.append(placeholder) }
        }
        return (AXHelpers.title(window).map { [$0] } ?? [], buttons, texts)
    }

    static func elements(in window: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= KktConstants.joinSnapshotDepth else { return }
            result.append(element)
            guard depth < KktConstants.joinSnapshotDepth else { return }
            for child in AXHelpers.children(element) {
                walk(child, depth: depth + KktConstants.joinDepthIncrement)
            }
        }
        walk(window, depth: KktConstants.joinInitialDepth)
        return result
    }
}

public final class JoinAXUI: JoinUI {
    struct Dependencies {
        var prepareWindows: () throws -> (app: AXUIElement, mainWindow: AXUIElement) = { try ChatOpener.prepareWindows() }
        var openURL: (URL) throws -> Void = { ChatOpener.openURL($0) }
        var windows: (AXUIElement) -> [AXUIElement] = AXHelpers.windows
        var identifier: (AXUIElement) -> String? = AXHelpers.identifier
        var title: (AXUIElement) -> String? = AXHelpers.title
        var closeWindow: (AXUIElement) -> Bool = AXHelpers.closeWindow
        var captureFocus: () -> (() -> Void) = {
            let guard_ = FocusGuard()
            return { guard_.restore() }
        }
    }

    private let dependencies: Dependencies
    private let knownChatTitles: () throws -> Set<String>
    private var titles: Set<String> = []
    private var app: AXUIElement?
    private var previousWindows: [AXUIElement] = []
    private var activeWindow: AXUIElement?
    private var restoreFocus: (() -> Void)?

    public convenience init(knownChatTitles: @escaping () throws -> Set<String>) {
        self.init(knownChatTitles: knownChatTitles, dependencies: Dependencies())
    }

    init(knownChatTitles: @escaping () throws -> Set<String>, dependencies: Dependencies) {
        self.knownChatTitles = knownChatTitles
        self.dependencies = dependencies
    }

    public func openURL(_ url: URL) throws {
        let (app, _) = try dependencies.prepareWindows()
        previousWindows = dependencies.windows(app)
        try UserWindowGuard.check(windows: previousWindows.map {
            WindowInfo(identifier: dependencies.identifier($0), title: dependencies.title($0))
        })
        self.app = app
        restoreFocus = dependencies.captureFocus()
        titles = try knownChatTitles()
        try dependencies.openURL(url)
    }

    public func newScreens() -> [JoinScreen]? {
        activeWindow = nil
        var screens: [JoinScreen] = []
        let windows = newWindows()
        if !windows.isEmpty { restoreFocus?() }
        for window in windows.reversed() {
            let snapshot = JoinScreenReader.snapshot(window: window)
            if let screen = classifyJoinScreen(windowTitles: snapshot.titles, buttonTitles: snapshot.buttons,
                                               texts: snapshot.texts, knownChatTitles: titles) {
                if activeWindow == nil { activeWindow = window }
                screens.append(screen)
            }
        }
        return screens.isEmpty ? nil : screens
    }

    public func press(_ label: String) throws {
        guard let window = activeWindow else { throw KktError.automation(KktConstants.automationCode) }
        let optionalProfile = label == KktConstants.joinKakaoProfileLabel
        let control = JoinScreenReader.elements(in: window).first { element in
            guard isChoiceControl(element), let title = AXHelpers.title(element) else { return false }
            return optionalProfile ? title.contains(label) : title == label
        }
        guard let control else {
            if optionalProfile { return }
            throw KktError.automation(KktConstants.automationCode)
        }
        guard AXHelpers.performAction(control, kAXPressAction as String) else {
            throw KktError.automation(KktConstants.automationCode)
        }
    }

    public func setNickname(_ name: String) throws {
        guard let window = activeWindow else { throw KktError.automation(KktConstants.automationCode) }
        let controls = JoinScreenReader.elements(in: window)
        if let option = controls.first(where: {
            isChoiceControl($0) && (AXHelpers.title($0)?.contains(KktConstants.joinNicknameLabel) == true)
        }), !AXHelpers.performAction(option, kAXPressAction as String) {
            throw KktError.automation(KktConstants.automationCode)
        }
        guard let field = JoinScreenReader.elements(in: window).first(where: {
            AXHelpers.role($0) == kAXTextFieldRole as String
                && AXHelpers.attribute($0, kAXPlaceholderValueAttribute as String) == KktConstants.joinNicknamePlaceholder
        }), BackgroundInput.setText(field, name) else {
            throw KktError.automation(KktConstants.automationCode)
        }
    }

    public func closeNewWindows() {
        defer { restoreFocus?(); restoreFocus = nil }
        for window in newWindows().reversed() { _ = dependencies.closeWindow(window) }
        activeWindow = nil
    }

    private func newWindows() -> [AXUIElement] {
        guard let app else { return [] }
        return dependencies.windows(app).filter { window in
            dependencies.identifier(window) != KktConstants.mainWindowIdentifier
                && !previousWindows.contains(where: { CFEqual($0, window) })
        }
    }

    private func isChoiceControl(_ element: AXUIElement) -> Bool {
        let role = AXHelpers.role(element)
        return role == kAXButtonRole as String || role == kAXRadioButtonRole as String
    }
}
