import AppKit
import ApplicationServices
import Foundation

public protocol ContactUI {
    func openRoom() throws
    func recognize() throws -> [TextBox]
    func click(_ p: CGPoint, label: String) throws
    func jumpToBottom()
    func pageUp()
    func activate() throws
    func restore()
    func waitNewChatWindow(title: String) -> Bool
    func closeAll()
}

public final class ContactFlow {
    private let ui: any ContactUI
    private let lookupChatId: (Int64) throws -> Int64?
    private let clock: () -> Date
    private let sleep: (TimeInterval) -> Void

    public init(ui: any ContactUI, lookupChatId: @escaping (Int64) throws -> Int64?,
                clock: @escaping () -> Date = { Date() },
                sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.ui = ui
        self.lookupChatId = lookupChatId
        self.clock = clock
        self.sleep = sleep
    }

    public func run(userId: Int64, nickname: String, dryRun: Bool = false) -> KktResult {
        do {
            if let chatId = try lookupChatId(userId) {
                return KktResult(result: KktConstants.alreadyContactResult, chatId: chatId)
            }
            guard !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw KktError.invalidNickname
            }
            defer { ui.closeAll() }
            try ui.openRoom()
            let boxes = try findCard(nickname: nickname)
            guard let button = locateCardButtons(boxes: boxes, nickname: nickname) else {
                throw KktError.automation(KktConstants.cardNotVisibleCode)
            }
            if dryRun {
                return KktResult(result: KktConstants.dryRunResult,
                                 reason: KktConstants.cardFoundPrefix + button.label)
            }
            let friendAdded = try clickCard(button, boxes: boxes)
            guard ui.waitNewChatWindow(title: nickname) else {
                throw KktError.automation(KktConstants.contactWindowMissingCode)
            }
            let chatId = try awaitChatId(userId: userId)
            return KktResult(result: KktConstants.openedResult, chatId: chatId, friendAdded: friendAdded)
        } catch {
            return KktResult(result: KktConstants.failedResult, reason: Self.failureReason(error))
        }
    }

    public static func failureReason(_ error: Error) -> String {
        if case KktError.automation(let reason) = error { return reason }
        return (error as? KktError)?.code ?? KktConstants.automationCode
    }

    private func findCard(nickname: String) throws -> [TextBox] {
        ui.jumpToBottom()
        sleep(KktConstants.actionSettle)
        var boxes = try ui.recognize()
        if locateCardButtons(boxes: boxes, nickname: nickname) != nil { return boxes }
        for _ in .zero..<KktConstants.cardScrollSteps {
            ui.pageUp()
            sleep(KktConstants.actionSettle)
            boxes = try ui.recognize()
            if locateCardButtons(boxes: boxes, nickname: nickname) != nil { return boxes }
        }
        throw KktError.automation(KktConstants.cardNotVisibleCode)
    }

    private func clickCard(_ button: (primary: CGPoint, label: String), boxes: [TextBox]) throws -> Bool {
        defer { ui.restore() }
        let deadline = clock().addingTimeInterval(KktConstants.contactForegroundTimeout)
        try ui.activate()
        try click(button.primary, label: button.label, boxes: boxes)
        return button.label == KktConstants.cardLabelProfile ? try openStranger(deadline: deadline) : false
    }

    private func openStranger(deadline: Date) throws -> Bool {
        var boxes = try awaitPopover(label: KktConstants.cardLabelAdd, deadline: deadline)
        for _ in .zero..<KktConstants.contactAddAttempts {
            guard let add = locatePopoverButton(boxes: boxes, label: KktConstants.cardLabelAdd) else {
                throw KktError.automation(KktConstants.buttonNotFoundCode)
            }
            try click(add, label: KktConstants.cardLabelAdd, boxes: boxes)
            sleep(KktConstants.actionSettle)
            boxes = try awaitPopover(label: KktConstants.cardLabelDirect, allowAdd: true, deadline: deadline)
            if let direct = locatePopoverButton(boxes: boxes, label: KktConstants.cardLabelDirect) {
                try click(direct, label: KktConstants.cardLabelDirect, boxes: boxes)
                return true
            }
        }
        throw KktError.automation(KktConstants.buttonNotFoundCode)
    }

    private func awaitPopover(label: String, allowAdd: Bool = false, deadline: Date) throws -> [TextBox] {
        while clock() < deadline {
            let boxes = try ui.recognize()
            guard clock() < deadline else { break }
            if locatePopoverButton(boxes: boxes, label: label) != nil { return boxes }
            if allowAdd, locatePopoverButton(boxes: boxes, label: KktConstants.cardLabelAdd) != nil { return boxes }
            sleep(KktConstants.windowPoll)
        }
        throw KktError.automation(KktConstants.buttonNotFoundCode)
    }

    private func awaitChatId(userId: Int64) throws -> Int64 {
        let deadline = clock().addingTimeInterval(KktConstants.joinDBTimeout)
        repeat {
            if let chatId = try lookupChatId(userId) { return chatId }
            sleep(KktConstants.windowPoll)
        } while clock() < deadline
        throw KktError.automation(KktConstants.contactNotConfirmedCode)
    }

    private func click(_ point: CGPoint, label: String, boxes: [TextBox]) throws {
        try validateContactClick(point, label: label, boxes: boxes)
        try ui.click(point, label: label)
    }
}

public final class ContactAXUI: ContactUI {
    struct Dependencies {
        var prepareWindows: () throws -> (app: AXUIElement, mainWindow: AXUIElement) = { try ChatOpener.prepareWindows() }
        var openChat: (SendTarget) throws -> AXUIElement = { try ChatOpener().open($0) }
        var windows: (AXUIElement) -> [AXUIElement] = AXHelpers.windows
        var identifier: (AXUIElement) -> String? = AXHelpers.identifier
        var title: (AXUIElement) -> String? = AXHelpers.title
        var closeWindow: (AXUIElement) -> Bool = AXHelpers.closeWindow
        var clock: () -> Date = { Date() }
        var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    }

    private let dependencies: Dependencies
    private let room: () throws -> RoomRow
    private let recognizeWindow: (AXUIElement) throws -> [TextBox]
    private var roomWindow: AXUIElement?
    private var app: AXUIElement?
    private var previousWindows: [AXUIElement] = []
    private var roomWindows: [AXUIElement] = []
    private var focusGuard: FocusGuard?
    private var foregroundDeadline: Date?

    public convenience init(room: @escaping () throws -> RoomRow,
                            recognizeWindow: @escaping (AXUIElement) throws -> [TextBox]) {
        self.init(room: room, recognizeWindow: recognizeWindow, dependencies: Dependencies())
    }

    init(room: @escaping () throws -> RoomRow, recognizeWindow: @escaping (AXUIElement) throws -> [TextBox],
         dependencies: Dependencies) {
        self.room = room
        self.recognizeWindow = recognizeWindow
        self.dependencies = dependencies
    }

    public func openRoom() throws {
        let room = try room()
        guard let code = room.openLinkCode, !room.displayName.isEmpty else {
            throw KktError.notFound(String(room.chatId))
        }
        let (app, _) = try dependencies.prepareWindows()
        previousWindows = dependencies.windows(app)
        try UserWindowGuard.check(windows: previousWindows.map {
            WindowInfo(identifier: dependencies.identifier($0), title: dependencies.title($0))
        })
        self.app = app
        do {
            roomWindow = try dependencies.openChat(.openLink(code: code, title: room.displayName))
        } catch let error as KktError where error == .chatWindowOpen || error == .kakaoInUse || error == .kakaoNotRunning {
            self.app = nil
            throw error
        }
        roomWindows = dependencies.windows(app)
    }

    public func recognize() throws -> [TextBox] {
        guard let roomWindow else { throw KktError.automation(KktConstants.contactWindowMissingCode) }
        return try recognizeWindow(roomWindow)
    }

    // Foreground exception: profile-card controls are absent from KakaoTalk's AX tree.
    public func activate() throws {
        focusGuard = FocusGuard(restoresCursor: true)
        foregroundDeadline = dependencies.clock().addingTimeInterval(KktConstants.contactForegroundTimeout)
        guard let roomWindow,
              let application = NSRunningApplication.runningApplications(withBundleIdentifier: KakaoApp.bundleId).first,
              application.activate(), AXHelpers.performAction(roomWindow, kAXRaiseAction as String) else {
            throw KktError.automation(KktConstants.automationCode)
        }
        dependencies.sleep(KktConstants.foregroundSettle)
    }

    public func restore() {
        focusGuard?.restore()
        focusGuard = nil
        foregroundDeadline = nil
    }

    public func click(_ p: CGPoint, label: String) throws {
        let boxes = try recognize()
        guard let foregroundDeadline, dependencies.clock() < foregroundDeadline else {
            throw KktError.automation(KktConstants.buttonNotFoundCode)
        }
        try validateContactClick(p, label: label, boxes: boxes)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: p, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: p, mouseButton: .left) else {
            throw KktError.automation(KktConstants.automationCode)
        }
        down.post(tap: .cghidEventTap)
        dependencies.sleep(KktConstants.contactClickInterval)
        up.post(tap: .cghidEventTap)
        dependencies.sleep(KktConstants.actionSettle)
    }

    public func jumpToBottom() {
        guard let area = messageScrollArea(), let bar = verticalScrollBar(in: area) else { return }
        _ = AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString,
                                        KktConstants.scrollToBottomValue as CFNumber)
    }

    public func pageUp() {
        guard let area = messageScrollArea(), let bar = verticalScrollBar(in: area) else { return }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXValueAttribute as CFString, &value) == .success,
              let current = value as? NSNumber else { return }
        let table = AXHelpers.children(area).first { AXHelpers.role($0) == kAXTableRole as String }
        let step = Self.scrollStep(areaHeight: AXHelpers.size(area)?.height,
                                   contentHeight: table.flatMap { AXHelpers.size($0)?.height })
        let next = Self.nextScrollValue(current: current.doubleValue, step: step)
        _ = AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, next as CFNumber)
    }

    public static func scrollStep(areaHeight: CGFloat?, contentHeight: CGFloat?) -> Double {
        guard let areaHeight, let contentHeight, areaHeight.isFinite, contentHeight.isFinite,
              areaHeight > .zero, contentHeight > .zero else { return KktConstants.scrollFallbackStep }
        return Double(areaHeight / contentHeight) * KktConstants.scrollPageFraction
    }

    public static func nextScrollValue(current: Double, step: Double) -> Double {
        max(.zero, current - step)
    }

    private func verticalScrollBar(in area: AXUIElement) -> AXUIElement? {
        AXHelpers.children(area).first {
            AXHelpers.role($0) == kAXScrollBarRole as String
                && AXHelpers.attribute($0, kAXOrientationAttribute as String) == kAXVerticalOrientationValue as String
        }
    }

    public func waitNewChatWindow(title: String) -> Bool {
        guard let app else { return false }
        let deadline = dependencies.clock().addingTimeInterval(KktConstants.openWindowTimeout)
        repeat {
            if newWindows(in: app, excluding: roomWindows).contains(where: {
                AXHelpers.title($0) == title
            }) { return true }
            dependencies.sleep(KktConstants.windowPoll)
        } while dependencies.clock() < deadline
        return false
    }

    public func closeAll() {
        defer { restore() }
        if let app {
            for window in newWindows(in: app, excluding: previousWindows).reversed() {
                _ = dependencies.closeWindow(window)
            }
        }
        roomWindow = nil
        app = nil
    }

    private func newWindows(in app: AXUIElement, excluding previous: [AXUIElement]) -> [AXUIElement] {
        dependencies.windows(app).filter { window in
            dependencies.identifier(window) != KktConstants.mainWindowIdentifier
                && !previous.contains(where: { CFEqual($0, window) })
        }
    }

    private func messageScrollArea() -> AXUIElement? {
        guard let roomWindow else { return nil }
        return AXHelpers.children(roomWindow).first { area in
            AXHelpers.role(area) == kAXScrollAreaRole as String
                && AXHelpers.children(area).contains { AXHelpers.role($0) == kAXTableRole as String }
        }
    }
}
