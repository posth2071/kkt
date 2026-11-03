import ApplicationServices
import Foundation
@testable import KktCore
import XCTest
private enum JoinFixture {
    static let code = "GhIjKl34"
    static let token = "MnOpQr56St"
    static let link = "https://open.kakao.com/o/GhIjKl34"
    static let variants = [link, "open.kakao.com/o/GhIjKl34?x=1", "http://open.kakao.com/o/GhIjKl34/",
                           "https://open.kakao.com/o/GhIjKl34/?x=1#fragment"]
    static let team = "https://invite.kakao.com/tc/MnOpQr56St"
    static let invalid = ["https://coupang.com/x", "https://smartstore.naver.com/x", "open.kakao.com/me/x",
                          "https://open.kakao.com/o/", "https://open.kakao.com/o/a/b",
                          "https://open.kakao.com.evil/o/x", "ftp://open.kakao.com/o/x"]
    static let openScheme = "kakaoopen://join?l=GhIjKl34"
    static let teamScheme = "kakaotalk://teamchat/join?token=MnOpQr56St"
    static let title = "테스트 방"
    static let nickname = "테스트 별명"
    static let full = "참여 인원이 가득 찼습니다"
    static let ended = "운영이 종료된 채팅방입니다"
    static let deleted = "삭제된 채팅방입니다"
    static let ineligible = "참여할 수 없습니다"
    static let condition = "조건을 만족하지 않습니다"
    static let passcode = "참여코드를 입력해주세요"
    static let unknown = "알 수 없는 안내"
    static let joined = "joined"
    static let already = "already_member"
    static let requested = "requested"
    static let password = "needs_password"
    static let fullResult = "full"
    static let endedResult = "ended"
    static let ineligibleResult = "ineligible"
    static let invalidLink = "invalid_link"
    static let notConfirmed = "join_not_confirmed"
    static let dryReasons = ["cover", "profile_choice", "team_request"]
    static let chatId: Int64 = 42
    static let epoch = 0.0
    static let zero = 0
    static let one = 1
    static let two = 2
    static let databaseExtension = ".db"
    static let sqlitePath = "/usr/bin/sqlite3"
    static let successStatus: Int32 = 0
    static let insertRoom = "INSERT INTO NTChatRoom VALUES (42,4,99,'테스트 방',0);"
    static let schema = """
        CREATE TABLE NTChatRoom (chatId INTEGER, type INTEGER, linkId INTEGER,
            chatName TEXT, directChatMemberUserId INTEGER);
        CREATE TABLE NTOpenLink (linkId INTEGER, linkUrl TEXT, linkName TEXT);
        CREATE TABLE NTChatMeta (chatId INTEGER, type INTEGER, groupNickname TEXT);
        CREATE TABLE NTUser (userId INTEGER, linkId INTEGER,
            friendNickName TEXT, displayName TEXT, nickName TEXT);
        INSERT INTO NTOpenLink VALUES (99,'https://open.kakao.com/o/GhIjKl34','테스트 방');
        """
}
private final class FakeJoinUI: JoinUI {
    var screens: [[JoinScreen]] = []
    var opens: [URL] = []
    var presses: [String] = []
    var nicknames: [String] = []
    var closes = JoinFixture.zero
    var pressError: KktError?
    var openError: KktError?
    var nicknameError: KktError?
    func openURL(_ url: URL) throws {
        opens.append(url)
        if let openError { throw openError }
    }
    func newScreens() -> [JoinScreen]? {
        guard !screens.isEmpty else { return nil }
        return screens.count > JoinFixture.one ? screens.removeFirst() : screens.first
    }
    func press(_ label: String) throws {
        if let pressError { throw pressError }
        presses.append(label)
    }
    func setNickname(_ name: String) throws {
        if let nicknameError { throw nicknameError }
        nicknames.append(name)
    }
    func closeNewWindows() { closes += JoinFixture.one }
}
final class JoinTests: XCTestCase {
    private func flow(_ ui: FakeJoinUI, lookup: @escaping (String) throws -> Int64? = { _ in nil }) -> JoinFlow {
        var now = Date(timeIntervalSince1970: JoinFixture.epoch)
        return JoinFlow(ui: ui, lookupChatId: lookup,
                        clock: { now }, sleep: { now.addTimeInterval($0) })
    }
    func testJoinRefusesWhenUserWindowOpen() {
        let main = AXUIElementCreateApplication(pid_t(JoinFixture.one))
        let chat = AXUIElementCreateApplication(pid_t(JoinFixture.two))
        var dependencies = ChatOpener.Dependencies()
        dependencies.frontmostBundleId = { nil }
        dependencies.runningPid = { pid_t(JoinFixture.one) }
        dependencies.appElement = { _ in main }
        dependencies.windows = { _ in [main, chat] }
        dependencies.identifier = { CFEqual($0, main) ? KktConstants.mainWindowIdentifier : nil }
        dependencies.title = { _ in JoinFixture.title }
        dependencies.captureFocus = { XCTFail(); return {} }
        var uiDependencies = JoinAXUI.Dependencies()
        uiDependencies.prepareWindows = { try ChatOpener.prepareWindows(dependencies: dependencies) }
        uiDependencies.openURL = { _ in XCTFail() }
        uiDependencies.closeWindow = { _ in XCTFail(); return false }
        let ui = JoinAXUI(knownChatTitles: { [] }, dependencies: uiDependencies)
        let result = JoinFlow(ui: ui, lookupChatId: { _ in nil }).run(url: JoinFixture.link)
        XCTAssertEqual(result, KktResult(result: KktConstants.failedResult, reason: KktError.chatWindowOpen.code))
    }
    func testJoinFailureClosesOnlyWindowsOpenedByKkt() {
        let main = AXUIElementCreateApplication(pid_t(JoinFixture.one))
        let cover = AXUIElementCreateApplication(pid_t(JoinFixture.two))
        let profile = AXUIElementCreateApplication(pid_t(JoinFixture.two + JoinFixture.one))
        var windows = [main]
        var closed: [AXUIElement] = []
        var dependencies = JoinAXUI.Dependencies()
        dependencies.prepareWindows = { (main, main) }
        dependencies.windows = { _ in windows }
        dependencies.identifier = { CFEqual($0, main) ? KktConstants.mainWindowIdentifier : nil }
        dependencies.title = { _ in nil }
        dependencies.captureFocus = { {} }
        dependencies.openURL = { _ in windows += [cover, profile]; throw KktError.busy }
        dependencies.closeWindow = { closed.append($0); return true }
        let ui = JoinAXUI(knownChatTitles: { [] }, dependencies: dependencies)
        let result = JoinFlow(ui: ui, lookupChatId: { _ in nil }).run(url: JoinFixture.link)
        XCTAssertEqual(result.reason, KktError.busy.code)
        XCTAssertEqual(closed.count, JoinFixture.two)
        XCTAssertTrue(CFEqual(closed[JoinFixture.zero], profile))
        XCTAssertTrue(CFEqual(closed[JoinFixture.one], cover))
        XCTAssertFalse(closed.contains(where: { CFEqual($0, main) }))
    }
    func testParseOpenLinkVariants() {
        for raw in JoinFixture.variants {
            XCTAssertEqual(JoinTarget.parse(raw), .openLink(code: JoinFixture.code))
        }
    }
    func testParseTeamInvite() {
        XCTAssertEqual(JoinTarget.parse(JoinFixture.team), .teamChat(token: JoinFixture.token))
    }
    func testParseRejectsOthers() {
        for raw in JoinFixture.invalid { XCTAssertNil(JoinTarget.parse(raw), raw) }
    }
    func testSchemeURLs() {
        XCTAssertEqual(schemeURL(for: .openLink(code: JoinFixture.code)).absoluteString, JoinFixture.openScheme)
        XCTAssertEqual(schemeURL(for: .teamChat(token: JoinFixture.token)).absoluteString, JoinFixture.teamScheme)
    }
    func testClassifyExistingChat() {
        XCTAssertEqual(classifyJoinScreen(windowTitles: [JoinFixture.title], buttonTitles: [], texts: [],
            knownChatTitles: [JoinFixture.title]), .existingChat(title: JoinFixture.title))
    }
    func testExistingChatHistoryIsNotAnOutcomeDialog() {
        XCTAssertEqual(classifyJoinScreen(windowTitles: [JoinFixture.title], buttonTitles: [],
            texts: [JoinFixture.full, JoinFixture.passcode], knownChatTitles: [JoinFixture.title]),
            .existingChat(title: JoinFixture.title))
    }
    func testClassifyCover() {
        XCTAssertEqual(classifyJoinScreen(windowTitles: [], buttonTitles: [KktConstants.joinButtonCover],
            texts: [JoinFixture.title], knownChatTitles: []), .cover(joinButton: true))
    }
    func testClassifyProfileChoice() {
        for (buttons, texts) in [([], [KktConstants.joinNicknamePlaceholder]),
                                  ([KktConstants.joinButtonConfirm], [])] {
            XCTAssertEqual(classifyJoinScreen(windowTitles: [], buttonTitles: buttons, texts: texts,
                knownChatTitles: []), .profileChoice)
        }
    }
    func testProfileChoiceIsRecognizedOverUnderlyingCover() {
        XCTAssertEqual(classifyJoinScreen(windowTitles: [],
            buttonTitles: [KktConstants.joinButtonCover, KktConstants.joinButtonConfirm],
            texts: [KktConstants.joinNicknamePlaceholder], knownChatTitles: []), .profileChoice)
    }
    func testClassifyPasscodeAndTeamRequest() {
        XCTAssertEqual(classifyJoinScreen(windowTitles: [], buttonTitles: [KktConstants.joinButtonConfirm],
            texts: [JoinFixture.passcode], knownChatTitles: []), .passcode)
        XCTAssertEqual(classifyJoinScreen(windowTitles: [], buttonTitles: [KktConstants.teamRequestButton],
            texts: [], knownChatTitles: []), .teamRequest)
        XCTAssertEqual(classifyJoinScreen(windowTitles: [], buttonTitles: [],
            texts: [KktConstants.teamRequestedMarker], knownChatTitles: []), .message(KktConstants.teamRequestedMarker))
        XCTAssertNil(classifyJoinScreen(windowTitles: [], buttonTitles: [], texts: [], knownChatTitles: []))
    }
    func testOutcomeMessages() {
        for (text, result) in [(JoinFixture.full, JoinFixture.fullResult), (JoinFixture.ended, JoinFixture.endedResult),
                               (JoinFixture.deleted, JoinFixture.endedResult),
                               (JoinFixture.ineligible, JoinFixture.ineligibleResult),
                               (JoinFixture.condition, JoinFixture.ineligibleResult)] {
            XCTAssertEqual(joinOutcome(screen: .message(text)), result)
        }
        XCTAssertEqual(joinOutcome(screen: .passcode), JoinFixture.password)
        XCTAssertNil(joinOutcome(screen: .profileChoice))
        XCTAssertNil(joinOutcome(screen: .message(JoinFixture.unknown)))
    }
    func testDryRunNeverPresses() {
        let screens: [JoinScreen] = [.cover(joinButton: true), .profileChoice, .teamRequest]
        for (screen, reason) in zip(screens, JoinFixture.dryReasons) {
            let ui = FakeJoinUI()
            ui.screens = [[screen]]
            let link = screen == .teamRequest ? JoinFixture.team : JoinFixture.link
            let result = flow(ui).run(url: link, profile: .nickname, nickname: JoinFixture.nickname, dryRun: true)
            XCTAssertEqual(result, KktResult(result: KktConstants.dryRunResult, reason: reason))
            XCTAssertTrue(ui.presses.isEmpty)
            XCTAssertTrue(ui.nicknames.isEmpty)
            XCTAssertEqual(ui.closes, JoinFixture.one)
        }
    }
    func testAlreadyMemberSkipsUI() {
        let ui = FakeJoinUI()
        let result = flow(ui, lookup: { code in
            XCTAssertEqual(code, JoinFixture.code)
            return JoinFixture.chatId
        }).run(url: JoinFixture.link)
        XCTAssertEqual(result, KktResult(result: JoinFixture.already, chatId: JoinFixture.chatId))
        XCTAssertTrue(ui.opens.isEmpty)
        XCTAssertTrue(ui.presses.isEmpty)
        XCTAssertEqual(ui.closes, JoinFixture.zero)
    }
    func testInvalidLinkSkipsDatabaseAndUI() {
        let ui = FakeJoinUI()
        let result = flow(ui, lookup: { _ in XCTFail(); return nil }).run(url: JoinFixture.invalid.first!)
        XCTAssertEqual(result, KktResult(result: KktConstants.failedResult, reason: JoinFixture.invalidLink))
        XCTAssertTrue(ui.opens.isEmpty)
    }
    func testJoinWaitsForDatabaseAndPressesEachStepOnce() {
        let ui = FakeJoinUI()
        ui.screens = [[.cover(joinButton: true)], [.cover(joinButton: true)], [.profileChoice]]
        var lookups = JoinFixture.zero
        let result = flow(ui, lookup: { _ in
            lookups += JoinFixture.one
            return lookups > JoinFixture.two ? JoinFixture.chatId : nil
        }).run(url: JoinFixture.link)
        XCTAssertEqual(result, KktResult(result: JoinFixture.joined, chatId: JoinFixture.chatId))
        XCTAssertEqual(ui.presses, [KktConstants.joinButtonCover, KktConstants.joinKakaoProfileLabel,
                                   KktConstants.joinButtonConfirm])
        XCTAssertEqual(ui.closes, JoinFixture.one)
    }
    func testNicknameIsSetBeforeConfirmation() {
        let ui = FakeJoinUI()
        ui.screens = [[.profileChoice]]
        var lookups = JoinFixture.zero
        let result = flow(ui, lookup: { _ in
            lookups += JoinFixture.one
            return lookups > JoinFixture.one ? JoinFixture.chatId : nil
        }).run(url: JoinFixture.link, profile: .nickname, nickname: JoinFixture.nickname)
        XCTAssertEqual(result.result, JoinFixture.joined)
        XCTAssertEqual(ui.nicknames, [JoinFixture.nickname])
        XCTAssertEqual(ui.presses, [KktConstants.joinButtonConfirm])
    }
    func testTeamRequestRequiresConfirmationAndSkipsOpenLinkLookup() {
        let ui = FakeJoinUI()
        ui.screens = [[.teamRequest], [.teamRequest], [.message(KktConstants.teamRequestedMarker)]]
        let result = flow(ui, lookup: { _ in XCTFail(); return nil }).run(url: JoinFixture.team)
        XCTAssertEqual(result.result, JoinFixture.requested)
        XCTAssertEqual(ui.presses, [KktConstants.teamRequestButton])
        XCTAssertEqual(ui.closes, JoinFixture.one)
    }
    func testExistingChatUsesDatabaseAndCloses() {
        let ui = FakeJoinUI()
        ui.screens = [[.existingChat(title: JoinFixture.title)]]
        var lookups = JoinFixture.zero
        let result = flow(ui, lookup: { _ in
            lookups += JoinFixture.one
            return lookups > JoinFixture.one ? JoinFixture.chatId : nil
        }).run(url: JoinFixture.link)
        XCTAssertEqual(result, KktResult(result: JoinFixture.already, chatId: JoinFixture.chatId))
        XCTAssertTrue(ui.presses.isEmpty)
        XCTAssertEqual(ui.closes, JoinFixture.one)
    }
    func testTerminalScreensCloseWithoutPressing() {
        for (screen, result) in [(JoinScreen.passcode, JoinFixture.password),
                                  (.message(JoinFixture.full), JoinFixture.fullResult)] {
            let ui = FakeJoinUI()
            ui.screens = [[screen]]
            XCTAssertEqual(flow(ui).run(url: JoinFixture.link).result, result)
            XCTAssertTrue(ui.presses.isEmpty)
            XCTAssertEqual(ui.closes, JoinFixture.one)
        }
    }
    func testJoinNotConfirmedAndScreenTimeoutCloseWindows() {
        for screens: [[JoinScreen]] in [[], [[.profileChoice]], [[.teamRequest]]] {
            let ui = FakeJoinUI()
            ui.screens = screens
            let result = flow(ui).run(url: screens == [[.teamRequest]] ? JoinFixture.team : JoinFixture.link)
            XCTAssertEqual(result.result, KktConstants.failedResult)
            XCTAssertEqual(ui.closes, JoinFixture.one)
            if screens == [[.profileChoice]] { XCTAssertEqual(result.reason, JoinFixture.notConfirmed) }
        }
    }
    func testErrorsUseKktErrorCodeAndCloseWindows() {
        let ui = FakeJoinUI()
        ui.screens = [[.cover(joinButton: true)]]
        ui.pressError = .busy
        let result = flow(ui).run(url: JoinFixture.link)
        XCTAssertEqual(result.reason, KktError.busy.code)
        XCTAssertEqual(ui.closes, JoinFixture.one)
    }
    func testFailureAfterProfileConfirmationIsClassified() {
        let ui = FakeJoinUI()
        ui.screens = [[.profileChoice], [.message(JoinFixture.full)]]
        let result = flow(ui).run(url: JoinFixture.link)
        XCTAssertEqual(result.result, JoinFixture.fullResult)
        XCTAssertEqual(ui.closes, JoinFixture.one)
    }
    func testMissingNicknameDoesNotOpenUI() {
        let ui = FakeJoinUI()
        let result = flow(ui).run(url: JoinFixture.link, profile: .nickname)
        XCTAssertEqual(result.reason, KktError.invalidNickname.code)
        XCTAssertTrue(ui.opens.isEmpty)
    }
    func testFailedOpenStillClosesNewWindows() {
        let ui = FakeJoinUI()
        ui.openError = .automation(JoinFixture.unknown)
        let result = flow(ui).run(url: JoinFixture.link)
        XCTAssertEqual(result.reason, KktConstants.automationCode)
        XCTAssertEqual(ui.closes, JoinFixture.one)
    }
    func testNicknameFailureNeverConfirmsJoin() {
        let ui = FakeJoinUI()
        ui.screens = [[.profileChoice]]
        ui.nicknameError = .automation(JoinFixture.unknown)
        let result = flow(ui).run(url: JoinFixture.link, profile: .nickname, nickname: JoinFixture.nickname)
        XCTAssertEqual(result.reason, KktConstants.automationCode)
        XCTAssertTrue(ui.presses.isEmpty)
        XCTAssertEqual(ui.closes, JoinFixture.one)
    }
    func testNewChatWindowWaitsForDatabaseRegistration() {
        let ui = FakeJoinUI()
        ui.screens = [[.profileChoice], [.message(JoinFixture.title)]]
        var lookups = JoinFixture.zero
        let result = flow(ui, lookup: { _ in
            lookups += JoinFixture.one
            return lookups > JoinFixture.two ? JoinFixture.chatId : nil
        }).run(url: JoinFixture.link)
        XCTAssertEqual(result, KktResult(result: JoinFixture.joined, chatId: JoinFixture.chatId))
        XCTAssertEqual(ui.closes, JoinFixture.one)
    }
    func testAlreadyMemberDoesNotRequireAnUnusedNickname() {
        let ui = FakeJoinUI()
        let result = flow(ui, lookup: { _ in JoinFixture.chatId })
            .run(url: JoinFixture.link, profile: .nickname)
        XCTAssertEqual(result, KktResult(result: JoinFixture.already, chatId: JoinFixture.chatId))
        XCTAssertTrue(ui.opens.isEmpty)
    }
}
final class JoinQueryTests: XCTestCase {
    private func write(_ sql: String, to path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: JoinFixture.sqlitePath)
        process.arguments = [path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, JoinFixture.successStatus)
    }
    func testJoinedChatLookupSeesNewWritesOnSameConnection() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + JoinFixture.databaseExtension).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try write(JoinFixture.schema, to: path)
        let reader = try KakaoDatabase.open(databasePath: path)
        defer { reader.close() }
        XCTAssertNil(try reader.joinedChatId(code: JoinFixture.code))
        try write(JoinFixture.insertRoom, to: path)
        XCTAssertEqual(try reader.joinedChatId(code: JoinFixture.code), JoinFixture.chatId)
        XCTAssertNil(try reader.joinedChatId(code: JoinFixture.token))
        XCTAssertEqual(try reader.knownJoinChatTitles(), [JoinFixture.title])
    }
}
