import ApplicationServices
@testable import KktCore
import XCTest

final class MainWindowReopenerTests: XCTestCase {
    func testMainWindowPresentIsUsedWithoutReopening() throws {
        let effects = Effects()
        effects.currentWindows = [KktConstants.selfChatName, KktConstants.mainWindowIdentifier]
        let result = try effects.find()
        XCTAssertEqual(result.mainWindow, KktConstants.mainWindowIdentifier)
        XCTAssertEqual(result.windows, effects.currentWindows)
        XCTAssertEqual(effects.reopenCount, .zero)
        XCTAssertTrue(effects.restoreTimes.isEmpty)
        XCTAssertTrue(effects.sleeps.isEmpty)
    }

    func testClosedMainWindowIsReopenedAndFocusRestoredOnce() throws {
        let effects = Effects()
        effects.availableAt = effects.now.addingTimeInterval(KktConstants.mainWindowPoll)
        let result = try effects.find()
        XCTAssertEqual(result.mainWindow, KktConstants.mainWindowIdentifier)
        XCTAssertEqual(result.windows, [KktConstants.selfChatName, KktConstants.mainWindowIdentifier])
        XCTAssertEqual(effects.reopenCount, KktConstants.singleUnit)
        XCTAssertEqual(effects.restoreTimes, [try XCTUnwrap(effects.availableAt)])
        XCTAssertEqual(effects.sleeps.last, KktConstants.actionSettle)
        XCTAssertTrue(effects.sleeps.dropLast().allSatisfy { $0 == KktConstants.mainWindowPoll })
        XCTAssertEqual(effects.now, effects.availableAt?.addingTimeInterval(KktConstants.actionSettle))
    }

    func testReopenTimeoutThrowsAutomationFailed() {
        let effects = Effects()
        let deadline = effects.now.addingTimeInterval(KktConstants.mainWindowReopenTimeout)
        XCTAssertThrowsError(try effects.find()) {
            XCTAssertEqual($0 as? KktError, .automation(KktConstants.automationCode))
        }
        XCTAssertEqual(effects.reopenCount, KktConstants.singleUnit)
        XCTAssertEqual(effects.now, deadline)
        XCTAssertTrue(effects.sleeps.allSatisfy { $0 > .zero && $0 <= KktConstants.mainWindowPoll })
    }

    func testFocusRestoredEvenWhenReopenTimesOut() {
        let effects = Effects()
        let deadline = effects.now.addingTimeInterval(KktConstants.mainWindowReopenTimeout)
        XCTAssertThrowsError(try effects.find())
        XCTAssertEqual(effects.restoreTimes, [deadline])
    }

    private final class Effects {
        var currentWindows: [String] = []
        var now = Date(timeIntervalSinceReferenceDate: .zero)
        var availableAt: Date?
        var reopenCount = Int.zero
        var restoreTimes: [Date] = []
        var sleeps: [TimeInterval] = []

        func find() throws -> (mainWindow: String, windows: [String]) {
            try MainWindowReopener.find(windows: {
                if let availableAt = self.availableAt, self.now >= availableAt,
                   self.reopenCount == KktConstants.singleUnit {
                    return [KktConstants.selfChatName, KktConstants.mainWindowIdentifier]
                }
                return self.currentWindows
            }, isMainWindow: { $0 == KktConstants.mainWindowIdentifier },
            reopen: { self.reopenCount += KktConstants.singleUnit },
            sleep: { self.sleeps.append($0); self.now.addTimeInterval($0) },
            clock: { self.now }, restoreFocus: { self.restoreTimes.append(self.now) })
        }
    }
}

final class FocusGuardTests: XCTestCase {
    func testRestoreCommandUsesBundleIdentifierArgument() {
        let bundleId = "com.orca.app"
        let command = FocusGuard.restoreCommand(bundleId: bundleId)
        XCTAssertEqual(command.path, "/usr/bin/open")
        XCTAssertEqual(command.args, ["-b", bundleId])
    }

    func testRestorationDecisionTable() {
        let orca = "com.orca.app"
        let kakao = KakaoApp.bundleId
        let cases: [(String?, String?, Bool)] = [
            (orca, kakao, true), (kakao, kakao, false), (kakao, orca, false),
            (orca, orca, false), (nil, kakao, false), (orca, nil, false), (nil, nil, false),
        ]
        for (previous, current, expected) in cases {
            XCTAssertEqual(FocusGuard.shouldRestore(previousBundleId: previous, currentBundleId: current), expected)
        }
    }
}

final class BackgroundInputTests: XCTestCase {
    func testReadBackNormalizesWhitespace() {
        let expected = "hello world 안녕"
        for actual in [expected, "  hello\tworld\n안녕  ", "hello\r\nworld\u{00a0}안녕"] {
            XCTAssertTrue(BackgroundInput.matchesReadBack(actual, expected: expected))
        }
        XCTAssertTrue(BackgroundInput.matchesReadBack(" \n\t", expected: ""))
    }

    func testReadBackRejectsMissingOrDifferentText() {
        XCTAssertFalse(BackgroundInput.matchesReadBack(nil, expected: ""))
        XCTAssertFalse(BackgroundInput.matchesReadBack("hello", expected: "hello world"))
        XCTAssertFalse(BackgroundInput.matchesReadBack("helloworld", expected: "hello world"))
    }
}

final class ChatOpenerTests: XCTestCase {
    func testRefusesWhileKakaoTalkIsFrontmost() {
        for target: SendTarget in [.selfChat(name: KktConstants.selfChatName),
                                   .direct(name: KktConstants.selfChatName),
                                   .group(name: KktConstants.selfChatName),
                                   .openLink(code: KktConstants.selfChatName, title: KktConstants.selfChatName)] {
            let effects = OpeningEffects()
            var dependencies = effects.dependencies()
            dependencies.frontmostBundleId = { KakaoApp.bundleId }
            dependencies.appElement = { _ in XCTFail(); return effects.app }
            dependencies.captureFocus = { XCTFail(); return {} }
            dependencies.windows = { _ in XCTFail(); return [] }
            dependencies.pressReturn = { _ in XCTFail() }
            XCTAssertThrowsError(try ChatOpener(dependencies: dependencies).open(target)) {
                XCTAssertEqual($0 as? KktError, .kakaoInUse)
                XCTAssertEqual(($0 as? KktError)?.code, KktConstants.Code.kakaoInUse)
            }
            XCTAssertTrue(effects.events.isEmpty)
        }
    }

    func testProceedsWhenKakaoTalkIsBackground() throws {
        let effects = OpeningEffects()
        var dependencies = effects.dependencies()
        var queries = Int.zero
        var frontmostBundleId: String?
        dependencies.frontmostBundleId = { queries += KktConstants.singleUnit; return frontmostBundleId }
        let opener = ChatOpener(dependencies: dependencies)
        XCTAssertTrue(CFEqual(try opener.open(.selfChat(name: KktConstants.selfChatName)), effects.chat))
        XCTAssertEqual(queries, KktConstants.singleUnit)
        XCTAssertFalse(effects.events.isEmpty)
        frontmostBundleId = KakaoApp.bundleId
        effects.events.removeAll()
        XCTAssertThrowsError(try opener.open(.selfChat(name: KktConstants.selfChatName))) {
            XCTAssertEqual($0 as? KktError, .kakaoInUse)
        }
        XCTAssertTrue(effects.events.isEmpty)
        XCTAssertEqual(queries, KktConstants.singleUnit + KktConstants.singleUnit)
    }

    func testPrepareWindowsRefusesWhileKakaoTalkIsFrontmost() {
        XCTAssertThrowsError(try ChatOpener.prepareWindows(frontmostBundleId: { KakaoApp.bundleId })) {
            XCTAssertEqual($0 as? KktError, .kakaoInUse)
        }
    }

    func testUiCommandFailsFastWhenKakaoTalkIsNotRunning() {
        var axCalls = 0
        var dependencies = ChatOpener.Dependencies()
        dependencies.runningPid = { nil }
        dependencies.frontmostBundleId = { nil }
        dependencies.appElement = { _ in axCalls += 1; return AXUIElementCreateApplication(-1) }
        dependencies.captureFocus = { axCalls += 1; return {} }
        XCTAssertThrowsError(try ChatOpener(dependencies: dependencies).open(.selfChat(name: KktConstants.selfChatName))) {
            XCTAssertEqual($0 as? KktError, .kakaoNotRunning)
            XCTAssertEqual(($0 as? KktError)?.code, "kakaotalk_not_running")
        }
        XCTAssertEqual(axCalls, 0)
    }

    func testTableFocusedBeforeReturn() throws {
        let effects = OpeningEffects()
        let result = try ChatOpener(dependencies: effects.dependencies()).open(.group(name: "엄마"))
        XCTAssertTrue(CFEqual(result, effects.chat))
        XCTAssertEqual(effects.events, ["select", "focus(table)", "return"])
    }

    func testVisibleRowDoesNotTouchSearch() throws {
        let effects = OpeningEffects()
        var searchCalls = Int.zero
        var dependencies = effects.dependencies()
        dependencies.search = { _, _ in
            searchCalls += KktConstants.singleUnit
            return nil
        }
        let result = try ChatOpener(dependencies: dependencies).open(.selfChat(name: KktConstants.selfChatName))
        XCTAssertTrue(CFEqual(result, effects.chat))
        XCTAssertEqual(searchCalls, .zero)
    }

    func testSelfChatSearchesOwnNameWhenNotVisible() throws {
        let effects = OpeningEffects()
        var query = KktConstants.emptyText
        var typed: [String] = []
        var dependencies = effects.dependencies()
        dependencies.search = { _, _ in
            ChatSearch(findField: { effects.table }, pressSearch: { true },
                read: { _ in query }, clear: { _ in query = KktConstants.emptyText; return true },
                type: { _, text in query = text; typed.append(text) }, sleep: { _ in })
        }
        dependencies.matchingRows = { _, name, selfChat in
            XCTAssertTrue(selfChat)
            XCTAssertEqual(name, KktConstants.selfChatName)
            return query == name ? [effects.row] : []
        }
        let result = try ChatOpener(dependencies: dependencies).open(.selfChat(name: KktConstants.selfChatName))
        XCTAssertTrue(CFEqual(result, effects.chat))
        XCTAssertEqual(typed, [KktConstants.selfChatName])
        XCTAssertEqual(query, KktConstants.emptyText)
    }

    func testSelfChatIgnoresSameNameRowWithoutBadge() {
        let effects = OpeningEffects()
        var query = KktConstants.emptyText
        var typed: [String] = []
        var dependencies = effects.dependencies()
        dependencies.search = { _, _ in
            ChatSearch(findField: { effects.table }, pressSearch: { true },
                read: { _ in query }, clear: { _ in query = KktConstants.emptyText; return true },
                type: { _, text in query = text; typed.append(text) }, sleep: { _ in })
        }
        dependencies.matchingRows = { _, _, selfChat in selfChat ? [] : [effects.row] }
        XCTAssertThrowsError(try ChatOpener(dependencies: dependencies).open(.selfChat(name: KktConstants.selfChatName))) {
            XCTAssertEqual($0 as? KktError, .notFound(KktConstants.selfChatName))
        }
        XCTAssertEqual(typed, [KktConstants.selfChatName])
        XCTAssertFalse(effects.opened)
        XCTAssertTrue(effects.events.isEmpty)
        XCTAssertEqual(query, KktConstants.emptyText)
    }

    func testScansScrolledSearchResultsForExactName() throws {
        for usesIndex in [true, false] {
            let effects = ScrolledOpeningEffects()
            effects.usesIndex = usesIndex
            let result = try ChatOpener(dependencies: effects.dependencies()).open(.direct(name: ScrollFixture.name))
            XCTAssertTrue(CFEqual(result, effects.opening.chat))
            XCTAssertEqual(effects.selectedIndices, [ScrollFixture.matchIndex])
            XCTAssertEqual(effects.scanValues, ScrollFixture.scanValues + [ScrollFixture.matchStep, .zero])
            XCTAssertEqual(effects.scrollSleeps, Array(repeating: ScrollFixture.settle,
                                                      count: effects.scanValues.count))
            XCTAssertTrue(effects.focusPreservedDuringScan)
            XCTAssertEqual(effects.query, ScrollFixture.original)
        }
    }

    func testScrolledScanRejectsTwoExactMatches() {
        let effects = ScrolledOpeningEffects()
        effects.matchIndices.insert(ScrollFixture.secondMatchIndex)
        XCTAssertThrowsError(try ChatOpener(dependencies: effects.dependencies()).open(.direct(name: ScrollFixture.name))) {
            XCTAssertEqual($0 as? KktError, .ambiguous(ScrollFixture.name))
        }
        XCTAssertTrue(effects.selectedIndices.isEmpty)
        XCTAssertFalse(effects.opening.opened)
        XCTAssertEqual(effects.scanValues, ScrollFixture.scanValues + [.zero])
    }

    func testSelfChatFoundBelowFold() throws {
        let effects = ScrolledOpeningEffects()
        effects.selfChat = true
        let result = try ChatOpener(dependencies: effects.dependencies()).open(.selfChat(name: ScrollFixture.name))
        XCTAssertTrue(CFEqual(result, effects.opening.chat))
        XCTAssertEqual(effects.selectedIndices, [ScrollFixture.matchIndex])
        XCTAssertEqual(effects.scanValues, ScrollFixture.scanValues + [ScrollFixture.matchStep, .zero])
    }

    func testScrollbarRestored() throws {
        for outcome in ScrollFixture.Outcome.allCases {
            let effects = ScrolledOpeningEffects()
            switch outcome {
            case .success: break
            case .notFound: effects.matchIndices = []
            case .ambiguous: effects.matchIndices.insert(ScrollFixture.secondMatchIndex)
            case .selectionFailure: effects.selectionSucceeds = false
            }
            let opener = ChatOpener(dependencies: effects.dependencies())
            if outcome == .success {
                _ = try opener.open(.direct(name: ScrollFixture.name))
            } else {
                XCTAssertThrowsError(try opener.open(.direct(name: ScrollFixture.name))) {
                    let expected: KktError = outcome == .ambiguous
                        ? .ambiguous(ScrollFixture.name) : .notFound(ScrollFixture.name)
                    XCTAssertEqual($0 as? KktError, expected)
                }
            }
            XCTAssertEqual(effects.scanValues.last, .zero)
            XCTAssertEqual(effects.scrollValueWhenRestoring, .zero)
            XCTAssertEqual(effects.query, ScrollFixture.original)
        }
    }

    func testOpenRejectsUserWindowAfterMainWindowRecovery() {
        let effects = OpeningEffects()
        effects.mainPresent = false
        effects.userWindowPresent = true
        XCTAssertThrowsError(try ChatOpener(dependencies: effects.dependencies()).open(.selfChat(name: KktConstants.selfChatName))) {
            XCTAssertEqual($0 as? KktError, .chatWindowOpen)
        }
        XCTAssertEqual(effects.events, ["reopen"])
    }

    func testOpenLinkCannotBypassUserWindowGuard() {
        let effects = OpeningEffects()
        effects.userWindowPresent = true
        XCTAssertThrowsError(try ChatOpener(dependencies: effects.dependencies())
            .open(.openLink(code: "fixture", title: "엄마"))) {
            XCTAssertEqual($0 as? KktError, .chatWindowOpen)
        }
        XCTAssertEqual(effects.events, [])
    }

    func testChatListRowsPreferVisibleRowsWithoutReadingChildren() {
        let visibleRows = [KktConstants.selfChatName]
        let rows = AXHelpers.chatListRows(visibleRows: { visibleRows }, children: {
            XCTFail()
            return [KktConstants.mainWindowIdentifier]
        })
        XCTAssertEqual(rows, visibleRows)
    }

    func testChatListRowsKeepAvailableEmptyVisibleRows() {
        let rows: [String] = AXHelpers.chatListRows(visibleRows: { [] }, children: {
            XCTFail()
            return [KktConstants.mainWindowIdentifier]
        })
        XCTAssertTrue(rows.isEmpty)
    }

    func testChatListRowsFallBackToChildrenWhenVisibleRowsUnavailable() {
        let children = [KktConstants.mainWindowIdentifier, KktConstants.selfChatName]
        let rows = AXHelpers.chatListRows(visibleRows: { nil }, children: { children })
        XCTAssertEqual(rows, children)
    }

    func testUntitledTransientWindowIsIgnored() {
        XCTAssertEqual(ChatOpener.pickOpenedWindow(titles: [""], expected: "모집방"), .waiting)
        XCTAssertEqual(ChatOpener.pickOpenedWindow(titles: [nil], expected: "모집방"), .waiting)
    }

    func testExpectedWindowFoundNextToTransient() {
        XCTAssertEqual(ChatOpener.pickOpenedWindow(titles: ["", "모집방"], expected: "모집방"), .found(1))
    }

    func testOtherTitledWindowIsUnexpected() {
        XCTAssertEqual(ChatOpener.pickOpenedWindow(titles: ["상대가"], expected: "모집방"), .unexpected)
    }

    private enum ScrollFixture {
        static let name = "레이"
        static let original = "이전 검색"
        static let rowCount = 78
        static let visibleCount = 12
        static let matchIndex = 34
        static let secondMatchIndex = 70
        static let matchStep = 0.375
        static let scanValues: [Double] = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1]
        static let settle = 0.25
        static let rowPidBase: pid_t = -1000
        static let scrollBarPid: pid_t = -6
        enum Outcome: CaseIterable { case success, notFound, ambiguous, selectionFailure }
    }

    private final class ScrolledOpeningEffects {
        let opening = OpeningEffects()
        let scrollBar = AXUIElementCreateApplication(ScrollFixture.scrollBarPid)
        var query = ScrollFixture.original
        var matchIndices: Set<Int> = [ScrollFixture.matchIndex]
        var usesIndex = true
        var selfChat = false
        var selectionSucceeds = true
        var scrollValue = Double.zero
        var scanValues: [Double] = []
        var scrollSleeps: [TimeInterval] = []
        var selectedIndices: [Int] = []
        var scrollValueWhenRestoring: Double?
        var focusPreservedDuringScan = true
        var generation = Int.zero
        var currentRows: [AXUIElement] = []

        var visibleIndices: Range<Int> {
            let start = Int((scrollValue * Double(ScrollFixture.rowCount - ScrollFixture.visibleCount)).rounded())
            return start..<(start + ScrollFixture.visibleCount)
        }

        func renderRows() {
            generation += KktConstants.one
            currentRows = (KktConstants.zero..<ScrollFixture.rowCount).map {
                AXUIElementCreateApplication(ScrollFixture.rowPidBase - pid_t(generation * ScrollFixture.rowCount + $0))
            }
        }

        func dependencies() -> ChatOpener.Dependencies {
            renderRows()
            var dependencies = opening.dependencies()
            dependencies.title = { element in
                CFEqual(element, self.opening.main) ? KktConstants.mainWindowIdentifier : ScrollFixture.name
            }
            dependencies.search = { _, _ in
                ChatSearch(findField: { self.opening.table }, pressSearch: { true },
                    read: { _ in self.query }, clear: { _ in self.query = KktConstants.emptyText; return true },
                    type: { _, text in
                        if text == ScrollFixture.original { self.scrollValueWhenRestoring = self.scrollValue }
                        self.query = text
                    }, sleep: { _ in })
            }
            dependencies.rows = { _ in self.currentRows }
            dependencies.visibleRows = { _ in self.visibleIndices.map { self.currentRows[$0] } }
            dependencies.rowIndex = { row in
                self.usesIndex ? self.currentRows.firstIndex(where: { CFEqual($0, row) }) : nil
            }
            dependencies.matchingRows = { _, name, selfChat in
                XCTAssertEqual(name, ScrollFixture.name)
                XCTAssertEqual(selfChat, self.selfChat)
                guard self.query == ScrollFixture.name else { return [] }
                return self.visibleIndices.filter { self.matchIndices.contains($0) }.map { self.currentRows[$0] }
            }
            dependencies.scrollBar = { _ in self.scrollBar }
            dependencies.setScrollValue = { element, value in
                XCTAssertTrue(CFEqual(element, self.scrollBar))
                if value != .zero {
                    self.focusPreservedDuringScan = self.focusPreservedDuringScan && self.opening.events.isEmpty
                }
                self.scrollValue = value
                self.scanValues.append(value)
                self.renderRows()
                return true
            }
            dependencies.selectRow = { row, _ in
                guard let index = self.currentRows.firstIndex(where: { CFEqual($0, row) }),
                      self.visibleIndices.contains(index) else {
                    XCTFail("Selection must use a freshly rendered visible row")
                    return false
                }
                self.selectedIndices.append(index)
                return self.selectionSucceeds
            }
            dependencies.sleep = { interval in
                if interval == ScrollFixture.settle { self.scrollSleeps.append(interval) }
                self.opening.now.addTimeInterval(interval)
            }
            return dependencies
        }
    }

    private final class OpeningEffects {
        let app = AXUIElementCreateApplication(-1)
        let main = AXUIElementCreateApplication(-2)
        let table = AXUIElementCreateApplication(-3)
        let row = AXUIElementCreateApplication(-4)
        let chat = AXUIElementCreateApplication(-5)
        var mainPresent = true
        var userWindowPresent = false
        var opened = false
        var events: [String] = []
        var now = Date(timeIntervalSince1970: 100)

        func dependencies() -> ChatOpener.Dependencies {
            var dependencies = ChatOpener.Dependencies()
            dependencies.frontmostBundleId = { nil }
            dependencies.runningPid = { -1 }
            dependencies.appElement = { _ in self.app }
            dependencies.captureFocus = { {} }
            dependencies.windows = { _ in
                (self.mainPresent ? [self.main] : [])
                    + (self.userWindowPresent || self.opened ? [self.chat] : [])
            }
            dependencies.identifier = { CFEqual($0, self.main) ? "Main Window" : "AXWindow-123" }
            dependencies.title = { CFEqual($0, self.main) ? "카카오톡" : "엄마" }
            dependencies.reopen = { self.events.append("reopen"); self.mainPresent = true }
            dependencies.openURL = { _ in XCTFail("Unexpected URL launch") }
            dependencies.chatroomsTab = { _ in nil }
            dependencies.search = { _, _ in nil }
            dependencies.table = { _ in self.table }
            dependencies.matchingRows = { _, _, _ in [self.row] }
            dependencies.selectRow = { _, _ in self.events.append("select"); return true }
            dependencies.focus = { element in
                XCTAssertTrue(CFEqual(element, self.table))
                self.events.append("focus(table)")
                return true
            }
            dependencies.pressReturn = { _ in self.events.append("return"); self.opened = true }
            dependencies.sleep = { self.now.addTimeInterval($0) }
            dependencies.clock = { self.now }
            return dependencies
        }
    }
}

final class UniqueRowTests: XCTestCase {
    func testOnlySingleMatchIsUsed() {
        XCTAssertEqual(ChatOpener.uniqueMatch([7]), 7)
        XCTAssertNil(ChatOpener.uniqueMatch([7, 8]))
        XCTAssertNil(ChatOpener.uniqueMatch([Int]()))
    }
}


final class FocusRestoreTests: XCTestCase {
    private enum Fixture {
        static let previous = "com.example.previous"
        static let other = "com.example.other"
        static let bundlelessPid: pid_t = 4242
        static let cursor = CGPoint(x: 10, y: 20)
        static let activationDelay: TimeInterval = 1.2
        static let activationLimit: TimeInterval = 2
    }

    private final class Recorder {
        var commands: [[String]] = []
        var cursors: [CGPoint] = []
    }

    private func focusGuard(current: String?, recorder: Recorder, restoresCursor: Bool = false) -> FocusGuard {
        FocusGuard(restoresCursor: restoresCursor, captureApplication: { Fixture.previous },
                   captureCursor: { Fixture.cursor }, currentApplication: { current },
                   run: { recorder.commands.append([$0] + $1) }, restoreCursor: { recorder.cursors.append($0) })
    }

    func testReturnsToPreviousAppWhenKakaoTalkIsFrontmost() {
        let recorder = Recorder()
        focusGuard(current: KakaoApp.bundleId, recorder: recorder).restore()
        let command = FocusGuard.restoreCommand(bundleId: Fixture.previous)
        XCTAssertEqual(recorder.commands, [[command.path] + command.args])
    }

    private func bundlelessGuard(current: String?, activated: Recorder) -> FocusGuard {
        FocusGuard(captureApplication: { nil }, captureProcess: { Fixture.bundlelessPid },
                   currentApplication: { current }, run: { activated.commands.append([$0] + $1) },
                   activate: { activated.commands.append([String($0)]) })
    }

    func testReturnsToAppWithoutBundleIdByProcess() {
        let recorder = Recorder()
        bundlelessGuard(current: KakaoApp.bundleId, activated: recorder).restore()
        XCTAssertEqual(recorder.commands, [[String(Fixture.bundlelessPid)]])
    }

    func testLeavesFocusAloneWhenAppWithoutBundleIdIsStillFrontmost() {
        let recorder = Recorder()
        bundlelessGuard(current: nil, activated: recorder).restore()
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testLeavesTheAppTheUserMovedToAlone() {
        let recorder = Recorder()
        focusGuard(current: Fixture.other, recorder: recorder).restore()
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testDoesNotReopenAnAppThatIsAlreadyFrontmost() {
        let recorder = Recorder()
        focusGuard(current: Fixture.previous, recorder: recorder).restore()
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testUnknownFrontmostAppIsLeftAlone() {
        let recorder = Recorder()
        focusGuard(current: nil, recorder: recorder).restore()
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testCursorIsRestoredEvenWhenTheAppIsLeftAlone() {
        let recorder = Recorder()
        focusGuard(current: Fixture.other, recorder: recorder, restoresCursor: true).restore()
        XCTAssertEqual(recorder.cursors, [Fixture.cursor])
    }

    private func reopen(activatesAfter delay: TimeInterval?) throws -> (restoredAt: TimeInterval?, count: Int) {
        var now = Date(timeIntervalSince1970: .zero)
        let start = now
        var opened = false, restoredAt: TimeInterval?, count = 0
        _ = try MainWindowReopener.find(
            windows: { opened ? [true] : [] }, isMainWindow: { $0 }, reopen: { opened = true },
            sleep: { now.addTimeInterval($0) }, clock: { now },
            restoreFocus: { count += 1; restoredAt = restoredAt ?? now.timeIntervalSince(start) },
            selfActivated: { delay.map { now.timeIntervalSince(start) >= $0 } ?? false })
        return (restoredAt, count)
    }

    func testReopenWaitsForKakaoTalkToActivateItselfBeforeRestoring() throws {
        let result = try reopen(activatesAfter: Fixture.activationDelay)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.restoredAt), Fixture.activationDelay)
        XCTAssertLessThan(try XCTUnwrap(result.restoredAt), Fixture.activationLimit)
    }

    func testReopenStopsWaitingWhenKakaoTalkNeverActivates() throws {
        let result = try reopen(activatesAfter: nil)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.restoredAt), Fixture.activationLimit)
        XCTAssertEqual(result.count, 1)
    }
}
