import AppKit
import ApplicationServices
import Foundation

public struct ImagePaste {
    typealias Clipboard = [[NSPasteboard.PasteboardType: Data]]

    struct Dependencies {
        var captureFocus: () -> (() -> Void) = {
            let guard_ = FocusGuard()
            return { guard_.restore() }
        }
        var activate: () throws -> Void = {
            guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: KakaoApp.bundleId).first,
                  application.activate() else { throw KktError.kakaoNotRunning }
        }
        var raise: (AXUIElement) -> Void = { _ = AXHelpers.performAction($0, kAXRaiseAction as String) }
        var click: (AXUIElement) throws -> Void = ImagePaste.click
        var readClipboard: () throws -> Clipboard = ImagePaste.readClipboard
        var restoreClipboard: (Clipboard) -> Void = ImagePaste.restoreClipboard
        var writeFiles: ([String]) -> Bool = { paths in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        }
        var paste: () throws -> Void = ImagePaste.paste
        var children: (AXUIElement) -> [AXUIElement] = AXHelpers.children
        var role: (AXUIElement) -> String? = AXHelpers.role
        var title: (AXUIElement) -> String? = AXHelpers.title
        var press: (AXUIElement) -> Bool = { AXHelpers.performAction($0, kAXPressAction as String) }
        var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
        var clock: () -> Date = { Date() }
    }
    private let dependencies: Dependencies
    public init() { dependencies = Dependencies() }
    init(dependencies: Dependencies) { self.dependencies = dependencies }

    public func send(in window: AXUIElement, input: AXUIElement, images: [String], pasteOnly: Bool = false) throws {
        guard !images.isEmpty else { return }
        let sheet = try paste(in: window, input: input, images: images)
        if pasteOnly { return }
        guard let button = dependencies.children(sheet).first(where: {
                  dependencies.role($0) == kAXButtonRole as String
                      && (dependencies.title($0) ?? KktConstants.emptyText).hasSuffix(KktConstants.imageSendSuffix)
              }), dependencies.title(button) == String(images.count) + KktConstants.imageSendSuffix else {
            throw KktError.automation(KktConstants.automationCode)
        }
        // The sheet closes as soon as the button fires, so AXPress may report an error for a press that worked
        // (2026-11-03: photo delivered, press returned failure). The sheet going away is the success signal.
        let pressed = dependencies.press(button)
        if !pressed && dependencies.children(window).contains(where: { CFEqual($0, sheet) }) {
            dependencies.sleep(KktConstants.imageSheetPoll)
            guard !dependencies.children(window).contains(where: { CFEqual($0, sheet) }) else {
                throw KktError.automation(KktConstants.automationCode)
            }
        }
        let deadline = dependencies.clock().addingTimeInterval(KktConstants.imageSheetTimeout)
        while dependencies.children(window).contains(where: { dependencies.role($0) == kAXSheetRole as String }) {
            let remaining = deadline.timeIntervalSince(dependencies.clock())
            guard remaining > KktConstants.zeroInterval else { return }
            dependencies.sleep(min(KktConstants.imageSheetPoll, remaining))
        }
    }

    private func paste(in window: AXUIElement, input: AXUIElement, images: [String]) throws -> AXUIElement {
        let restore = dependencies.captureFocus()
        defer { restore() }
        try dependencies.activate()
        dependencies.raise(window)
        dependencies.sleep(KktConstants.actionSettle)
        try dependencies.click(input)
        dependencies.sleep(KktConstants.actionSettle)
        let clipboard = try dependencies.readClipboard()
        defer { dependencies.restoreClipboard(clipboard) }
        guard dependencies.writeFiles(images) else { throw KktError.automation(KktConstants.automationCode) }
        dependencies.sleep(KktConstants.actionSettle)
        try dependencies.paste()
        let deadline = dependencies.clock().addingTimeInterval(KktConstants.imageSheetTimeout)
        while true {
            if let sheet = dependencies.children(window).first(where: { dependencies.role($0) == kAXSheetRole as String }) {
                return sheet
            }
            let remaining = deadline.timeIntervalSince(dependencies.clock())
            guard remaining > KktConstants.zeroInterval else { throw KktError.automation(KktConstants.automationCode) }
            dependencies.sleep(min(KktConstants.imageSheetPoll, remaining))
        }
    }

    private static func readClipboard() throws -> Clipboard {
        try (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    throw KktError.automation(KktConstants.automationCode)
                }
                contents[type] = data
            }
            return contents
        }
    }

    private static func restoreClipboard(_ contents: Clipboard) {
        let pasteboard = NSPasteboard.general
        let items = contents.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private static func paste() throws {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: KktConstants.pasteKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: KktConstants.pasteKey, keyDown: false) else {
            throw KktError.automation(KktConstants.automationCode)
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func click(_ element: AXUIElement) throws {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            throw KktError.automation(KktConstants.automationCode)
        }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            throw KktError.automation(KktConstants.automationCode)
        }
        let center = CGPoint(x: position.x + size.width / KktConstants.clickCenterDivisor,
                             y: position.y + size.height / KktConstants.clickCenterDivisor)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                      mouseCursorPosition: center, mouseButton: .left) else {
                throw KktError.automation(KktConstants.automationCode)
            }
            event.post(tap: .cghidEventTap)
        }
    }
}
