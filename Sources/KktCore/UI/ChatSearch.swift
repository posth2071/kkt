import ApplicationServices
import Foundation

public final class ChatSearch {
    private let field: AXUIElement
    private let read: (AXUIElement) -> String?
    private let clearField: (AXUIElement) -> Bool
    private let typeField: (AXUIElement, String) -> Void
    private let pressSearch: () -> Bool
    private let sleep: (TimeInterval) -> Void
    private var restored = false
    public let original: String
    public let openedByKkt: Bool

    public convenience init?(mainWindow: AXUIElement, pid: pid_t) {
        self.init(findField: {
            AXHelpers.findAll(mainWindow, role: KktConstants.AX.textField).first
        }, pressSearch: {
            guard let button = AXHelpers.findAll(mainWindow, role: KktConstants.AX.button).first(where: {
                AXHelpers.description($0) == KktConstants.searchButtonDescription
            }) else { return false }
            return AXHelpers.performAction(button, kAXPressAction as String)
        }, read: AXHelpers.value, clear: { field in
            guard let button = AXHelpers.children(field).first(where: {
                Self.isClearButton(role: AXHelpers.role($0), title: AXHelpers.title($0),
                                   description: AXHelpers.description($0))
            }) else { return false }
            return AXHelpers.performAction(button, kAXPressAction as String)
        }, type: { field, text in
            guard AXHelpers.focus(field) else { return }
            BackgroundInput.typeText(text, pid: pid)
        }, sleep: { Thread.sleep(forTimeInterval: $0) })
    }

    init?(findField: () -> AXUIElement?, pressSearch: @escaping () -> Bool,
          read: @escaping (AXUIElement) -> String?, clear: @escaping (AXUIElement) -> Bool,
          type: @escaping (AXUIElement, String) -> Void, sleep: @escaping (TimeInterval) -> Void) {
        var field = findField()
        let openedByKkt = field == nil
        if openedByKkt {
            guard pressSearch() else { return nil }
            sleep(KktConstants.searchClearPoll)
            field = findField()
            if field == nil { _ = pressSearch() }
        }
        guard let field else { return nil }
        self.field = field
        self.original = read(field) ?? KktConstants.emptyText
        self.openedByKkt = openedByKkt
        self.read = read
        self.clearField = clear
        self.typeField = type
        self.pressSearch = pressSearch
        self.sleep = sleep
    }

    public static func isClearButton(role: String?, title: String?, description: String?) -> Bool {
        role == KktConstants.AX.button && [title, description].contains(KktConstants.searchClearButtonTitle)
    }

    @discardableResult
    public func clear() -> Bool {
        guard !(read(field) ?? KktConstants.emptyText).isEmpty else { return true }
        guard clearField(field) else { return false }
        sleep(KktConstants.searchClearPoll)
        return true
    }

    public func type(_ text: String) {
        typeField(field, text)
    }

    public func restore() {
        guard !restored else { return }
        if (read(field) ?? KktConstants.emptyText) != original {
            guard clear() else { return }
            if !original.isEmpty { type(original) }
        }
        if openedByKkt {
            guard pressSearch() else { return }
        }
        restored = true
    }
}
