import ApplicationServices
@testable import KktCore
import XCTest
private enum ContactFixture {
    static let nickname = "상대가"
    static let link = "https://open.kakao.com/o/test"
    static let existingName = "상대나"
    static let missingName = "없는 이름"
    static let chatId: Int64 = 42
    static let userId: Int64 = 99
    static let zero = 0
    static let one = 1
    static let two = 2
    static let epoch = 0.0
    static let add = "친구 추가"
    static let profile = "프로필 보기"
    static let direct = "1:1 채팅"
    static let block = "차단"
    static let report = "신고"
    static let call = "통화"
    static let opened = "opened"
    static let already = "already_contact"
    static let cardMissing = "card_not_visible"
    static let buttonMissing = "button_not_found"
    static let forbidden = "forbidden_label"
    static let permission = "screen_recording_permission"
    static let dryReason = "card_found:프로필 보기"
    static let preview = "상대가 : 새 메시지"
    static let lock = "대화할 때 주의가 필요한 방입니다."
    static let stranger = [box(nickname, 105, 1083, 40, 20), box(add, 50, 1122, 76, 22),
                           box(profile, 132, 1122, 76, 22)]
    static let existing = [box(existingName, 105, 1190, 40, 20), box(direct, 50, 1265, 76, 22),
                           box(profile, 132, 1265, 76, 22)]
    static let popover = [box(nickname, 105, 900, 40, 20), box(add, 50, 1000, 76, 22),
                          box(block, 132, 1000, 76, 22), box(report, 220, 1050, 76, 22)]
    static let added = [box(nickname, 105, 900, 40, 20), box(direct, 50, 1000, 76, 22),
                        box(call, 132, 1000, 76, 22)]
    static let shifted = stranger.map {
        TextBox(text: $0.text, rect: $0.rect.offsetBy(dx: .zero, dy: 30))
    }
    static let forbiddenCard = stranger + [box(block, 132, 1122, 76, 22)]
    static let previewBoxes = stranger + [box(preview, 30, 1300, 200, 22), box(lock, 30, 1380, 300, 22)]
    static let normalized = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.1)
    static let window = CGRect(x: -500, y: 200, width: 400, height: 800)
    static let converted = CGRect(x: -400, y: 760, width: 200, height: 80)
    static let databaseExtension = ".db"
    static let sqlite = "/usr/bin/sqlite3"
    static let schema = """
        CREATE TABLE NTChatRoom (chatId INTEGER, directChatMemberUserId INTEGER, type INTEGER);
        INSERT INTO NTChatRoom VALUES (7,99,1);
        INSERT INTO NTChatRoom VALUES (8,88,0);
        """
    static let insertDirect = "INSERT INTO NTChatRoom VALUES (42,99,0);"
    static func box(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> TextBox {
        TextBox(text: text, rect: CGRect(x: x, y: y, width: w, height: h))
    }
}
private final class FakeContactUI: ContactUI {
    var screens: [[TextBox]] = [ContactFixture.stranger, ContactFixture.popover, ContactFixture.added]
    var stage = ContactFixture.zero
    var clicks: [(CGPoint, String)] = []
    var opens = ContactFixture.zero
    var closes = ContactFixture.zero
    var scrolls = ContactFixture.zero
    var upwardScrolls = ContactFixture.zero
    var recognitions = ContactFixture.zero
    var dismissMenuFirst = false
    var foundWindow = true
    var recognizeError: KktError?
    var openError: KktError?
    var scrolledBoxes: [TextBox]?
    var waitedTitles: [String] = []
    var activations = ContactFixture.zero
    var restorations = ContactFixture.zero
    var clickError: KktError?
    var scrollCalls: [String] = []
    var restorationsWhenWaiting: Int?
    var activateError: KktError?
    func activate() throws {
        activations += ContactFixture.one
        if let activateError { throw activateError }
    }
    func restore() { restorations += ContactFixture.one }
    func openRoom() throws {
        opens += ContactFixture.one
        if let openError { throw openError }
    }
    func recognize() throws -> [TextBox] {
        recognitions += ContactFixture.one
        if let recognizeError { throw recognizeError }
        if stage == ContactFixture.zero, scrolls > ContactFixture.zero, let scrolledBoxes { return scrolledBoxes }
        return screens[min(stage, screens.count - ContactFixture.one)]
    }
    func click(_ p: CGPoint, label: String) throws {
        clicks.append((p, label))
        if let clickError { throw clickError }
        if label == ContactFixture.add, dismissMenuFirst { dismissMenuFirst = false; return }
        if label == ContactFixture.profile || label == ContactFixture.add { stage += ContactFixture.one }
    }
    func jumpToBottom() { scrolls += ContactFixture.one; scrollCalls.append("jumpToBottom") }
    func pageUp() { upwardScrolls += ContactFixture.one; scrollCalls.append("pageUp") }
    func waitNewChatWindow(title: String) -> Bool {
        restorationsWhenWaiting = restorations
        waitedTitles.append(title)
        return foundWindow
    }
    func closeAll() { closes += ContactFixture.one }
}
final class ContactTests: XCTestCase {
    func testContactRefusesWhenUserWindowOpen() {
        for nested in [false, true] {
            let main = AXUIElementCreateApplication(pid_t(ContactFixture.one)), chat = AXUIElementCreateApplication(pid_t(ContactFixture.two))
            var windows = [main]
            var dependencies = ChatOpener.Dependencies()
            dependencies.frontmostBundleId = { nil }; dependencies.runningPid = { pid_t(ContactFixture.one) }
            dependencies.appElement = { _ in main }
            dependencies.windows = { _ in nested ? windows : [main, chat] }
            dependencies.identifier = { CFEqual($0, main) ? KktConstants.mainWindowIdentifier : nil }
            dependencies.title = { _ in nil }; dependencies.captureFocus = { XCTFail(); return {} }
            var uiDependencies = ContactAXUI.Dependencies()
            uiDependencies.prepareWindows = { try ChatOpener.prepareWindows(dependencies: dependencies) }
            uiDependencies.windows = { _ in windows }; uiDependencies.identifier = dependencies.identifier
            uiDependencies.title = dependencies.title
            uiDependencies.openChat = { _ in windows.append(chat); throw KktError.chatWindowOpen }
            uiDependencies.closeWindow = { _ in XCTFail(); return false }
            let ui = ContactAXUI(room: {
                RoomRow(chatId: ContactFixture.chatId, type: ContactFixture.one, linkId: ContactFixture.userId,
                        linkUrl: ContactFixture.link, displayName: ContactFixture.nickname)
            }, recognizeWindow: { _ in XCTFail(); return [] }, dependencies: uiDependencies)
            let result = ContactFlow(ui: ui, lookupChatId: { _ in nil }).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
            XCTAssertEqual(result, KktResult(result: KktConstants.failedResult, reason: KktError.chatWindowOpen.code))
        }
    }
    func testContactFailureClosesOnlyWindowsOpenedByKkt() {
        let main = AXUIElementCreateApplication(pid_t(ContactFixture.one)), room = AXUIElementCreateApplication(pid_t(ContactFixture.two))
        let popover = AXUIElementCreateApplication(pid_t(ContactFixture.two + ContactFixture.one))
        let direct = AXUIElementCreateApplication(pid_t(ContactFixture.two + ContactFixture.two))
        var windows = [main], closed: [AXUIElement] = []
        var dependencies = ContactAXUI.Dependencies()
        dependencies.prepareWindows = { (main, main) }; dependencies.windows = { _ in windows }
        dependencies.identifier = { CFEqual($0, main) ? KktConstants.mainWindowIdentifier : nil }; dependencies.title = { _ in nil }
        dependencies.openChat = { _ in windows += [room, popover, direct]; throw KktError.busy }
        dependencies.closeWindow = { closed.append($0); return true }
        let ui = ContactAXUI(room: {
            RoomRow(chatId: ContactFixture.chatId, type: ContactFixture.one, linkId: ContactFixture.userId,
                    linkUrl: ContactFixture.link, displayName: ContactFixture.nickname)
        }, recognizeWindow: { _ in XCTFail(); return [] }, dependencies: dependencies)
        let result = ContactFlow(ui: ui, lookupChatId: { _ in nil }).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(result.reason, KktError.busy.code)
        XCTAssertEqual(closed.count, ContactFixture.two + ContactFixture.one)
        XCTAssertTrue(CFEqual(closed[ContactFixture.zero], direct) && CFEqual(closed[ContactFixture.one], popover))
        XCTAssertTrue(CFEqual(closed[ContactFixture.two], room))
        XCTAssertFalse(closed.contains(where: { CFEqual($0, main) }))
    }
    func testScrollStepUsesVisibleFractionOfContent() {
        XCTAssertEqual(ContactAXUI.scrollStep(areaHeight: 891, contentHeight: 30000),
                       891.0 / 30000.0 * 0.9, accuracy: 0.000001)
    }
    func testScrollStepFallsBackWhenHeightsAreUnavailableOrInvalid() {
        let heights: [(CGFloat?, CGFloat?)] = [
            (nil, nil), (nil, 30000), (891, nil), (.zero, 30000),
            (891, .zero), (-891, 30000), (891, -30000), (.infinity, 30000), (891, .nan),
        ]
        for (area, content) in heights {
            XCTAssertEqual(ContactAXUI.scrollStep(areaHeight: area, contentHeight: content), 0.03)
        }
    }
    func testNextScrollValueMovesUpAndClampsAtTop() {
        XCTAssertEqual(ContactAXUI.nextScrollValue(current: 1.0, step: 0.03), 0.97, accuracy: 0.000001)
        XCTAssertEqual(ContactAXUI.nextScrollValue(current: 0.5, step: 0.03), 0.47, accuracy: 0.000001)
        XCTAssertEqual(ContactAXUI.nextScrollValue(current: 0.02, step: 0.03), .zero)
        XCTAssertEqual(ContactAXUI.nextScrollValue(current: .zero, step: 0.03), .zero)
    }
    private func flow(_ ui: FakeContactUI, lookup: @escaping (Int64) throws -> Int64? = { _ in nil }) -> ContactFlow {
        var now = Date(timeIntervalSince1970: ContactFixture.epoch)
        return ContactFlow(ui: ui, lookupChatId: lookup, clock: { now }, sleep: { now.addTimeInterval($0) })
    }
    private func newContactFlow(_ ui: FakeContactUI) -> ContactFlow {
        var lookups = ContactFixture.zero
        return flow(ui, lookup: { userId in
            XCTAssertEqual(userId, ContactFixture.userId)
            lookups += ContactFixture.one
            return lookups > ContactFixture.two ? ContactFixture.chatId : nil
        })
    }
    func testCardWithExistingChatReturnsDirectButton() {
        let found = locateCardButtons(boxes: ContactFixture.existing, nickname: ContactFixture.existingName)
        XCTAssertEqual(found?.label, ContactFixture.direct)
        XCTAssertEqual(found?.primary, CGPoint(x: 88, y: 1276))
    }
    func testCardForStrangerReturnsProfileButton() {
        let found = locateCardButtons(boxes: ContactFixture.stranger, nickname: ContactFixture.nickname)
        XCTAssertEqual(found?.label, ContactFixture.profile)
        XCTAssertEqual(found?.primary, CGPoint(x: 170, y: 1133))
    }
    func testPicksLowestCardWhenNicknameRepeats() {
        let boxes = ContactFixture.stranger + ContactFixture.shifted
        XCTAssertEqual(locateCardButtons(boxes: boxes, nickname: ContactFixture.nickname)?.primary,
                       CGPoint(x: 170, y: 1163))
    }
    func testPopoverNeverReturnsReportOrBlock() {
        for label in [ContactFixture.report, ContactFixture.block] {
            XCTAssertNil(locatePopoverButton(boxes: ContactFixture.popover, label: label))
        }
        XCTAssertEqual(locatePopoverButton(boxes: ContactFixture.popover, label: ContactFixture.add),
                       CGPoint(x: 88, y: 1011))
    }
    func testPopoverDoesNotMistakeCardButtonForPopover() {
        XCTAssertNil(locatePopoverButton(boxes: ContactFixture.stranger, label: ContactFixture.add))
    }
    func testNoCardReturnsNil() {
        XCTAssertNil(locateCardButtons(boxes: ContactFixture.stranger, nickname: ContactFixture.missingName))
        XCTAssertNil(locateCardButtons(boxes: [], nickname: ContactFixture.nickname))
    }
    func testButtonsMustBelongToNicknameRow() {
        let boxes = [ContactFixture.box(ContactFixture.nickname, 500, 1083, 40, 20)]
            + Array(ContactFixture.stranger.dropFirst())
        XCTAssertNil(locateCardButtons(boxes: boxes, nickname: ContactFixture.nickname))
        let distant = [ContactFixture.box(ContactFixture.nickname, 105, 800, 40, 20)]
            + Array(ContactFixture.stranger.dropFirst())
        XCTAssertNil(locateCardButtons(boxes: distant, nickname: ContactFixture.nickname))
    }
    func testVisionCoordinatesUseTopLeftWindowPoints() {
        XCTAssertEqual(ScreenText.globalRect(normalized: ContactFixture.normalized,
                                              windowFrame: ContactFixture.window), ContactFixture.converted)
    }
    func testForbiddenLabelsAreRejectedBeforePointValidation() {
        for label in [ContactFixture.block, ContactFixture.report] {
            XCTAssertThrowsError(try validateContactClick(.zero, label: label, boxes: [])) {
                XCTAssertEqual($0 as? KktError, .automation(ContactFixture.forbidden))
            }
        }
    }
    func testDryRunClicksNothing() {
        let ui = FakeContactUI()
        ui.screens = [ContactFixture.previewBoxes]
        let result = flow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname, dryRun: true)
        XCTAssertEqual(result, KktResult(result: KktConstants.dryRunResult, reason: ContactFixture.dryReason))
        XCTAssertTrue(ui.clicks.isEmpty)
        XCTAssertTrue(ui.waitedTitles.isEmpty)
        XCTAssertEqual(ui.closes, ContactFixture.one)
        XCTAssertEqual(ui.activations, ContactFixture.zero)
        XCTAssertEqual(ui.restorations, ContactFixture.zero)
    }
    func testRealClicksActivateOnceAndRestoreOnce() {
        let ui = FakeContactUI()
        _ = newContactFlow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(ui.activations, ContactFixture.one)
        XCTAssertEqual(ui.restorations, ContactFixture.one)
        XCTAssertEqual(ui.restorationsWhenWaiting, ContactFixture.one)
    }
    func testActivationFailureStillRestoresAndDoesNotClick() {
        let ui = FakeContactUI()
        ui.activateError = .automation(ContactFixture.buttonMissing)
        let result = flow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(result.reason, ContactFixture.buttonMissing)
        XCTAssertEqual(ui.activations, ContactFixture.one)
        XCTAssertEqual(ui.restorations, ContactFixture.one)
        XCTAssertTrue(ui.clicks.isEmpty)
    }
    func testClickFailureStillRestoresFocus() {
        let ui = FakeContactUI()
        ui.clickError = .automation(ContactFixture.buttonMissing)
        let result = flow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(result.reason, ContactFixture.buttonMissing)
        XCTAssertEqual(ui.activations, ContactFixture.one)
        XCTAssertEqual(ui.restorations, ContactFixture.one)
        XCTAssertEqual(ui.closes, ContactFixture.one)
    }
    func testSearchJumpsToBottomThenPagesUpWithoutActivation() {
        let ui = FakeContactUI()
        ui.screens = [[]]
        _ = flow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname, dryRun: true)
        XCTAssertEqual(ui.scrollCalls, ["jumpToBottom"] + Array(repeating: "pageUp", count: KktConstants.cardScrollSteps))
        XCTAssertEqual(ui.activations, ContactFixture.zero)
    }
    func testDryRunCanFindCardByScrollingWithoutClicking() {
        let ui = FakeContactUI()
        ui.screens = [[]]
        ui.scrolledBoxes = ContactFixture.stranger
        let result = flow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname, dryRun: true)
        XCTAssertEqual(result.reason, ContactFixture.dryReason)
        XCTAssertTrue(ui.clicks.isEmpty)
        XCTAssertEqual(ui.closes, ContactFixture.one)
    }
    func testForbiddenLabelNeverClicked() {
        let ui = FakeContactUI()
        ui.screens = [ContactFixture.forbiddenCard]
        let result = flow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(result.reason, ContactFixture.forbidden)
        XCTAssertTrue(ui.clicks.isEmpty)
        XCTAssertEqual(ui.closes, ContactFixture.one)
    }
    func testStrangerFlowOrder() {
        let ui = FakeContactUI()
        let result = newContactFlow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(ui.clicks.map(\.1), [ContactFixture.profile, ContactFixture.add, ContactFixture.direct])
        XCTAssertEqual(result, KktResult(result: ContactFixture.opened, chatId: ContactFixture.chatId, friendAdded: true))
        XCTAssertEqual(ui.waitedTitles, [ContactFixture.nickname])
        XCTAssertEqual(ui.closes, ContactFixture.one)
    }
    func testFriendAddRetriesOnceAfterMenuDismissal() {
        let ui = FakeContactUI()
        ui.dismissMenuFirst = true
        let result = newContactFlow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(ui.clicks.map(\.1), [ContactFixture.profile, ContactFixture.add,
                                           ContactFixture.add, ContactFixture.direct])
        XCTAssertEqual(result.friendAdded, true)
    }
    func testFriendAddStopsAfterOneRetry() {
        let ui = FakeContactUI()
        ui.screens = [ContactFixture.stranger, ContactFixture.popover]
        let result = flow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(result.reason, ContactFixture.buttonMissing)
        XCTAssertEqual(ui.clicks.map(\.1), [ContactFixture.profile, ContactFixture.add, ContactFixture.add])
    }
    func testAlreadyContactUsesZeroUI() {
        let ui = FakeContactUI()
        let result = flow(ui, lookup: { _ in ContactFixture.chatId })
            .run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(result, KktResult(result: ContactFixture.already, chatId: ContactFixture.chatId))
        XCTAssertEqual(ui.opens, ContactFixture.zero)
        XCTAssertEqual(ui.recognitions, ContactFixture.zero)
        XCTAssertEqual(ui.closes, ContactFixture.zero)
        XCTAssertTrue(ui.clicks.isEmpty)
    }
    func testExistingContactCardDoesNotAddFriend() {
        let ui = FakeContactUI()
        ui.screens = [ContactFixture.existing]
        let result = newContactFlow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.existingName)
        XCTAssertEqual(ui.clicks.map(\.1), [ContactFixture.direct])
        XCTAssertEqual(result.friendAdded, false)
    }
    func testScrollReRecognizesShiftedCard() {
        let ui = FakeContactUI()
        ui.scrolledBoxes = ContactFixture.shifted
        _ = newContactFlow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(ui.clicks.first?.0, CGPoint(x: 170, y: 1163))
        XCTAssertEqual(ui.scrolls, ContactFixture.one)
        XCTAssertGreaterThan(ui.recognitions, ui.scrolls)
    }
    func testJumpsToBottomInsteadOfClickingPreview() {
        let ui = FakeContactUI()
        ui.screens[ContactFixture.zero] = ContactFixture.previewBoxes
        _ = newContactFlow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertNotEqual(ui.clicks.first?.1, ContactFixture.preview)
        XCTAssertEqual(ui.scrolls, ContactFixture.one)
    }
    func testMissingCardFailsAndCloses() {
        let ui = FakeContactUI()
        ui.screens = [[]]
        let result = flow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
        XCTAssertEqual(result.reason, ContactFixture.cardMissing)
        XCTAssertEqual(ui.scrolls, ContactFixture.one)
        XCTAssertEqual(ui.upwardScrolls, KktConstants.cardScrollSteps)
        XCTAssertTrue(ui.clicks.isEmpty)
        XCTAssertEqual(ui.closes, ContactFixture.one)
    }
    func testPermissionAndOpenFailuresCloseWindows() {
        for failOpening in [true, false] {
            let ui = FakeContactUI()
            if failOpening { ui.openError = .automation(ContactFixture.permission) }
            else { ui.recognizeError = .automation(ContactFixture.permission) }
            let result = flow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
            XCTAssertEqual(result.reason, ContactFixture.permission)
            XCTAssertTrue(ui.clicks.isEmpty)
            XCTAssertEqual(ui.closes, ContactFixture.one)
        }
    }
    func testMissingWindowAndDatabaseTimeoutNeverReturnOpened() {
        for foundWindow in [true, false] {
            let ui = FakeContactUI()
            ui.foundWindow = foundWindow
            let result = flow(ui).run(userId: ContactFixture.userId, nickname: ContactFixture.nickname)
            XCTAssertEqual(result.result, KktConstants.failedResult)
            XCTAssertEqual(ui.closes, ContactFixture.one)
        }
    }
}
final class ContactQueryTests: XCTestCase {
    private func write(_ sql: String, to databasePath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ContactFixture.sqlite)
        process.arguments = [databasePath, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, .zero)
    }
    func testDirectLookupFiltersTypeAndSeesNewWrites() throws {
        let databasePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ContactFixture.databaseExtension).path
        defer { try? FileManager.default.removeItem(atPath: databasePath) }
        try write(ContactFixture.schema, to: databasePath)
        let reader = try KakaoDatabase.open(databasePath: databasePath)
        defer { reader.close() }
        XCTAssertNil(try reader.directChatId(userId: ContactFixture.userId))
        try write(ContactFixture.insertDirect, to: databasePath)
        XCTAssertEqual(try reader.directChatId(userId: ContactFixture.userId), ContactFixture.chatId)
    }
}
