import AppKit
import ApplicationServices

public struct NoticeAX {
    struct Dependencies {
        var open: (SendTarget) throws -> AXUIElement = { try ChatOpener().open($0) }
        var runningPid: () -> pid_t? = KakaoApp.runningPid
        var appElement: (pid_t) -> AXUIElement = AXUIElementCreateApplication
        var windows: (AXUIElement) -> [AXUIElement] = AXHelpers.windows
        var children: (AXUIElement) -> [AXUIElement] = AXHelpers.children
        var role: (AXUIElement) -> String? = AXHelpers.role
        var identifier: (AXUIElement) -> String? = AXHelpers.identifier
        var description: (AXUIElement) -> String? = AXHelpers.description
        var value: (AXUIElement) -> String? = AXHelpers.value
        var position: (AXUIElement) -> CGPoint? = AXHelpers.position
        var size: (AXUIElement) -> CGSize? = AXHelpers.size
        var visibleRows: (AXUIElement) -> [AXUIElement]? = {
            AXHelpers.elements($0, attribute: kAXVisibleRowsAttribute as String)
        }
        var captureFocus: (Bool) -> (() -> Void) = {
            let guard_ = FocusGuard(restoresCursor: $0)
            return { guard_.restore() }
        }
        var raise: (AXUIElement) -> Bool = { AXHelpers.performAction($0, kAXRaiseAction as String) }
        var activate: () throws -> Void = {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: KakaoApp.bundleId).first,
                  app.activate() else { throw KktError.kakaoNotRunning }
        }
        var click: (CGPoint) throws -> Void = NoticeAX.click
        var close: (AXUIElement) -> Void = { _ = AXHelpers.closeWindow($0) }
        var clock: () -> Date = Date.init
        var sleep: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    }

    private let dependencies: Dependencies

    public init() { dependencies = Dependencies() }
    init(dependencies: Dependencies) { self.dependencies = dependencies }

    public func read(_ target: SendTarget) throws -> String? {
        let room = try dependencies.open(target)
        var board: AXUIElement?
        var restore: (() -> Void)?
        defer {
            restore?()
            if let board { dependencies.close(board) }
            dependencies.close(room)
        }
        guard let banner = banner(in: room, depth: KktConstants.AX.searchDepth),
              let position = dependencies.position(banner), let size = dependencies.size(banner),
              position.x.isFinite, position.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > KktConstants.zeroInterval, size.height > KktConstants.zeroInterval else { return nil }
        guard let pid = dependencies.runningPid() else { throw KktError.kakaoNotRunning }
        let app = dependencies.appElement(pid)
        let previousWindows = dependencies.windows(app)
        try UserWindowGuard.check(windows: previousWindows.filter { !CFEqual($0, room) }.map {
            WindowInfo(identifier: dependencies.identifier($0), title: nil)
        })
        restore = dependencies.captureFocus(true)
        guard dependencies.raise(room) else { throw KktError.automation(KktConstants.automationCode) }
        try dependencies.activate()
        dependencies.sleep(KktConstants.foregroundSettle)
        let point = CGPoint(x: position.x + min(KktConstants.NoticeAX.clickInset,
                                                size.width / KktConstants.clickCenterDivisor),
                            y: position.y + size.height / KktConstants.clickCenterDivisor)
        try dependencies.click(point)
        let deadline = dependencies.clock().addingTimeInterval(KktConstants.NoticeAX.timeout)
        while true {
            if board == nil {
                board = dependencies.windows(app).first { window in
                    dependencies.identifier(window) == KktConstants.NoticeAX.window
                        && !previousWindows.contains { CFEqual($0, window) }
                }
            }
            if let board, let text = text(in: board) { return text }
            let remaining = deadline.timeIntervalSince(dependencies.clock())
            guard remaining > KktConstants.zeroInterval else { return nil }
            dependencies.sleep(min(KktConstants.windowPoll, remaining))
        }
    }

    private func banner(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth > KktConstants.zero, dependencies.role(element) != KktConstants.AX.table else { return nil }
        let children = dependencies.children(element)
        // 26.9 puts an action-less AXButton (and sometimes a "new" dot image) between the notice icon and its text.
        if let icon = children.firstIndex(where: {
            dependencies.role($0) == KktConstants.AX.image
                && dependencies.description($0)?.hasPrefix(KktConstants.NoticeAX.iconPrefix) == true
        }), let label = children[children.index(after: icon)...].first(where: {
            dependencies.role($0) == KktConstants.AX.staticText && hasNoIdentifier($0)
        }) { return label }
        return children.lazy.compactMap { banner(in: $0, depth: depth - KktConstants.one) }.first
    }

    private func text(in window: AXUIElement) -> String? {
        guard let table = descendants(window, depth: KktConstants.AX.searchDepth).first(where: {
            dependencies.role($0) == KktConstants.AX.table
                && dependencies.identifier($0) == KktConstants.NoticeAX.table
        }) else { return nil }
        let rows = dependencies.visibleRows(table) ?? dependencies.children(table)
        for row in rows where dependencies.role(row) == KktConstants.AX.row {
            for cell in dependencies.children(row) where dependencies.role(cell) == KktConstants.AX.cell {
                let contents = descendants(cell, depth: KktConstants.AX.searchDepth)
                guard contents.contains(where: {
                    dependencies.role($0) == KktConstants.AX.staticText
                        && dependencies.identifier($0) == KktConstants.NoticeAX.marker
                        && dependencies.value($0)?.contains(KktConstants.NoticeAX.noticeMarker) == true
                }), let body = contents.first(where: {
                    dependencies.role($0) == KktConstants.NoticeAX.textArea && hasNoIdentifier($0)
                }), let text = dependencies.value(body), !text.isEmpty else { continue }
                return text
            }
        }
        return nil
    }

    private func descendants(_ element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth > KktConstants.zero, dependencies.role(element) != KktConstants.AX.table else { return [element] }
        return [element] + dependencies.children(element).flatMap {
            descendants($0, depth: depth - KktConstants.one)
        }
    }

    private func hasNoIdentifier(_ element: AXUIElement) -> Bool {
        dependencies.identifier(element)?.isEmpty != false
    }

    private static func click(_ point: CGPoint) throws {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else {
            throw KktError.automation(KktConstants.automationCode)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

extension KktConstants {
    enum NoticeAX {
        static let window = "_NS:17"
        static let table = "_NS:95"
        static let marker = "_NS:57"
        static let textArea = "AXTextArea"
        static let noticeMarker = "공지"
        static let iconPrefix = "chatroom icon noti"
        static let clickInset: CGFloat = 40
        static let timeout: TimeInterval = 3
    }
}
