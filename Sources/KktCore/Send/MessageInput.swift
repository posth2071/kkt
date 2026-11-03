import ApplicationServices
import Foundation

public struct MessageInput {
    struct Dependencies {
        var frontmostBundleId: () -> String? = KakaoApp.frontmostBundleId
        var children: (AXUIElement) -> [AXUIElement] = AXHelpers.children
        var role: (AXUIElement) -> String? = AXHelpers.role
        var value: (AXUIElement) -> String? = AXHelpers.value
        var setText: (AXUIElement, String) -> Bool = BackgroundInput.setText
        var pid: (AXUIElement) -> pid_t? = { window in
            var pid: pid_t = .zero
            return AXUIElementGetPid(window, &pid) == .success ? pid : nil
        }
        var pressReturn: (pid_t) -> Void = BackgroundInput.pressReturn
        var pasteImages: (AXUIElement, AXUIElement, [String]) throws -> Void = {
            try ImagePaste().send(in: $0, input: $1, images: $2)
        }
    }
    private let dependencies: Dependencies
    public init() { dependencies = Dependencies() }
    init(dependencies: Dependencies) { self.dependencies = dependencies }

    public func inputState(of window: AXUIElement) -> InputState {
        let texts = dependencies.children(window).filter {
            dependencies.role($0) == kAXStaticTextRole as String
        }.compactMap(dependencies.value)
        return classifyInput(windowTexts: texts, hasField: messageInputField(in: window) != nil)
    }

    public func messageInputField(in window: AXUIElement) -> AXUIElement? {
        for child in dependencies.children(window) {
            guard dependencies.role(child) == kAXScrollAreaRole as String else { continue }
            let children = dependencies.children(child)
            guard !children.contains(where: { dependencies.role($0) == kAXTableRole as String }) else { continue }
            if let input = children.first(where: { dependencies.role($0) == kAXTextAreaRole as String }) { return input }
        }
        return nil
    }

    public func send(in window: AXUIElement, message: String, images: [String]) throws {
        guard !message.isEmpty || !images.isEmpty else { return }
        try KakaoApp.checkNotInUse(frontmostBundleId: dependencies.frontmostBundleId)
        guard let input = messageInputField(in: window) else { throw KktError.automation(KktConstants.automationCode) }
        if !images.isEmpty { try dependencies.pasteImages(window, input, images) }
        guard !message.isEmpty else { return }
        guard let pid = dependencies.pid(window), dependencies.setText(input, message) else {
            throw KktError.automation(KktConstants.automationCode)
        }
        dependencies.pressReturn(pid)
    }
}

public final class SendOperation {
    struct Dependencies {
        var room: (Int64) throws -> RoomRow? = { _ in nil }
        var sameNameCount: (String) throws -> Int = { _ in KktConstants.noMatchingNames }
        var currentMaxLogId: () throws -> Int64 = { KktConstants.noLogId }
        var myUserId: () throws -> Int64 = { KktConstants.noLogId }
        var open: (SendTarget) throws -> AXUIElement = { try ChatOpener().open($0) }
        var close: (AXUIElement) -> Void = { _ = AXHelpers.closeWindow($0) }
        var isWindowOpen: (AXUIElement) -> Bool = { AXHelpers.role($0) == kAXWindowRole as String }
        var children: (AXUIElement) -> [AXUIElement] = AXHelpers.children
        var role: (AXUIElement) -> String? = AXHelpers.role
        var title: (AXUIElement) -> String? = AXHelpers.title
        var value: (AXUIElement) -> String? = AXHelpers.value
        var press: (AXUIElement) -> Bool = { AXHelpers.performAction($0, kAXPressAction as String) }
        var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
        var clock: () -> Date = { Date() }
        var inputState: (AXUIElement) -> InputState = { MessageInput().inputState(of: $0) }
        var send: (AXUIElement, String, [String]) throws -> Void = { try MessageInput().send(in: $0, message: $1, images: $2) }
        var wait: () throws -> Void = {}
        var record: () throws -> Void = {}
        var verify: (Int64, Int64, Int64, String, TimeInterval) throws -> SendVerifier.Outcome = { _, _, _, _, _ in .uncertain }
    }
    private let dependencies: Dependencies
    init(dependencies: Dependencies) { self.dependencies = dependencies }

    public convenience init(reader: KakaoDatabase, interval: SendInterval) {
        var dependencies = Dependencies()
        dependencies.room = reader.room
        dependencies.sameNameCount = reader.sameNameCount
        dependencies.currentMaxLogId = reader.currentMaxLogId
        dependencies.myUserId = reader.myUserId
        dependencies.wait = { try interval.waitIfNeeded() }
        dependencies.record = interval.record
        dependencies.verify = { chatId, start, myUserId, text, timeout in
            try SendVerifier.await(poll: KktConstants.sendVerifyPoll, timeout: timeout,
                myUserId: myUserId, startLogId: start, text: text,
                fetch: { try reader.sentRows(chatId: chatId, after: start) },
                sleep: { Thread.sleep(forTimeInterval: $0) }, clock: { Date() })
        }
        self.init(dependencies: dependencies)
    }

    public func execute(chatId: Int64, text: String, images: [String], dryRun: Bool) throws -> KktResult {
        guard let room = try dependencies.room(chatId) else { throw KktError.notFound(String(chatId)) }
        let count = room.needsNameLookup ? try dependencies.sameNameCount(room.displayName) : KktConstants.noMatchingNames
        let target = try resolveTarget(chatId: chatId, room: room, sameNameCount: count)
        let start = try dependencies.currentMaxLogId()
        let window = try dependencies.open(target)
        let result: KktResult
        do {
            switch dependencies.inputState(window) {
            case .locked: throw KktError.inputLocked
            case .missing: throw KktError.automation(KktConstants.automationCode)
            case .ready: break
            }
            if dryRun {
                result = KktResult(result: KktConstants.dryRunResult, chatId: chatId)
            } else {
                let myUserId = try dependencies.myUserId()
                let paths = images.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
                try dependencies.wait()
                try dependencies.send(window, text, paths)
                try dependencies.record()
                let timeout = images.isEmpty ? KktConstants.sendVerifyTimeout : KktConstants.imageVerifyTimeout
                switch try dependencies.verify(chatId, start, myUserId, text, timeout) {
                case .sent(let logId): result = KktResult(result: KktConstants.sentResult, chatId: chatId, logId: logId)
                case .uncertain: result = KktResult(result: KktConstants.uncertainResult, chatId: chatId)
                }
            }
        } catch {
            guard closeSafely(window) else { return KktResult(result: KktConstants.uncertainResult, chatId: chatId) }
            throw error
        }
        guard closeSafely(window) else { return KktResult(result: KktConstants.uncertainResult, chatId: chatId) }
        return result
    }

    private enum SheetOutcome {
        case ready
        case closeCancelled
        case timedOut
    }

    private func closeSafely(_ window: AXUIElement) -> Bool {
        guard waitForSheets(in: window, until: dependencies.clock().addingTimeInterval(KktConstants.imageSheetTimeout)) == .ready else {
            return false
        }
        dependencies.close(window)
        let deadline = dependencies.clock().addingTimeInterval(KktConstants.imageSheetTimeout)
        var retryClose = false
        while dependencies.clock() < deadline {
            let sheetOutcome = waitForSheets(in: window, until: deadline)
            guard sheetOutcome != .timedOut else { return false }
            if sheetOutcome == .closeCancelled { retryClose = true }
            if !dependencies.isWindowOpen(window) { return true }
            let remaining = deadline.timeIntervalSince(dependencies.clock())
            guard remaining > KktConstants.zeroInterval else { return false }
            dependencies.sleep(min(KktConstants.imageSheetPoll, remaining))
            if retryClose && dependencies.clock() < deadline,
               !dependencies.children(window).contains(where: { dependencies.role($0) == kAXSheetRole as String }) {
                dependencies.close(window)
                retryClose = false
            }
        }
        return false
    }

    private func waitForSheets(in window: AXUIElement, until deadline: Date) -> SheetOutcome {
        while dependencies.clock() < deadline {
            let sheets = dependencies.children(window).filter { dependencies.role($0) == kAXSheetRole as String }
            for sheet in sheets {
                let elements = descendants(of: sheet, depth: KktConstants.AX.searchDepth)
                if elements.contains(where: {
                    (dependencies.title($0) ?? KktConstants.emptyText).contains(KktConstants.uploadCancelWarning)
                        || (dependencies.value($0) ?? KktConstants.emptyText).contains(KktConstants.uploadCancelWarning)
                }) {
                    if let cancel = elements.first(where: {
                        dependencies.role($0) == kAXButtonRole as String
                            && dependencies.title($0) == KktConstants.uploadCancelButton
                    }), dependencies.press(cancel) { return .closeCancelled }
                }
            }
            if sheets.isEmpty { return .ready }
            let remaining = deadline.timeIntervalSince(dependencies.clock())
            guard remaining > KktConstants.zeroInterval else { return .timedOut }
            dependencies.sleep(min(KktConstants.imageSheetPoll, remaining))
        }
        return .timedOut
    }

    private func descendants(of element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth > KktConstants.zero else { return [element] }
        return [element] + dependencies.children(element).flatMap {
            descendants(of: $0, depth: depth - KktConstants.one)
        }
    }
}
