import ApplicationServices
import XCTest
@testable import KktCore

final class SkyLightFocusTests: XCTestCase {
    private enum Fixture {
        static let pid: pid_t = 401
        static let windowId: UInt32 = 0x0A0B0C0D
        static let serial: [UInt32] = [0, 77]
        static let recordSize = 0xf8
        static let sizeOffset = 0x04
        static let kindOffset = 0x08
        static let windowOffset = 0x3c
        static let focusStateOffset = 0x8a
        static let keyFlagOffset = 0x3a
        static let keyMaskRange = 0x20..<0x30
        static let focusKind: UInt8 = 0x0d
        static let acquireState: UInt8 = 1
        static let releaseState: UInt8 = 2
        static let keyDownKind: UInt8 = 1
        static let keyUpKind: UInt8 = 2
        static let keyFlag: UInt8 = 0x10
        static let mask: UInt8 = 0xff
        static let windowBytes: [UInt8] = [0x0D, 0x0C, 0x0B, 0x0A]
    }

    private final class Recorder {
        var records: [[UInt8]] = []
        var failAt: Int?

        func api(windowId: UInt32? = Fixture.windowId) -> SkyLightFocus.API {
            SkyLightFocus.API(windowId: { _ in windowId }, processSerial: { _ in Fixture.serial }, post: { serial, record in
                XCTAssertEqual(serial, Fixture.serial)
                self.records.append(record)
                return self.records.count - 1 != self.failAt
            })
        }
    }

    private func focus(_ api: SkyLightFocus.API?) -> SkyLightFocus {
        SkyLightFocus(api: api, pid: { _ in Fixture.pid }, sleep: { _ in })
    }

    private var window: AXUIElement { AXUIElementCreateApplication(Fixture.pid) }

    func testFocusRecordLayout() {
        let record = SkyLightFocus.focusRecord(windowId: Fixture.windowId, state: Fixture.acquireState)
        XCTAssertEqual(record.count, Fixture.recordSize)
        XCTAssertEqual(record[Fixture.sizeOffset], UInt8(Fixture.recordSize))
        XCTAssertEqual(record[Fixture.kindOffset], Fixture.focusKind)
        XCTAssertEqual(record[Fixture.focusStateOffset], Fixture.acquireState)
        XCTAssertEqual(Array(record[Fixture.windowOffset..<Fixture.windowOffset + Fixture.windowBytes.count]), Fixture.windowBytes)
    }

    func testKeyRecordLayout() {
        let record = SkyLightFocus.keyRecord(windowId: Fixture.windowId, kind: Fixture.keyUpKind)
        XCTAssertEqual(record.count, Fixture.recordSize)
        XCTAssertEqual(record[Fixture.sizeOffset], UInt8(Fixture.recordSize))
        XCTAssertEqual(record[Fixture.kindOffset], Fixture.keyUpKind)
        XCTAssertEqual(record[Fixture.keyFlagOffset], Fixture.keyFlag)
        XCTAssertTrue(record[Fixture.keyMaskRange].allSatisfy { $0 == Fixture.mask })
        XCTAssertEqual(Array(record[Fixture.windowOffset..<Fixture.windowOffset + Fixture.windowBytes.count]), Fixture.windowBytes)
    }

    func testAcquirePostsFocusThenKeyRecordsAndReleaseRevertsFocus() throws {
        let recorder = Recorder()
        let release = try XCTUnwrap(focus(recorder.api()).acquire(window: window))
        XCTAssertEqual(recorder.records.map { $0[Fixture.kindOffset] }, [Fixture.focusKind, Fixture.keyDownKind, Fixture.keyUpKind])
        release()
        XCTAssertEqual(recorder.records.last?[Fixture.kindOffset], Fixture.focusKind)
        XCTAssertEqual(recorder.records.last?[Fixture.focusStateOffset], Fixture.releaseState)
    }

    func testMissingSymbolsAcquireNothing() {
        XCTAssertNil(focus(nil).acquire(window: window))
    }

    func testMissingWindowPostsNothing() {
        let recorder = Recorder()
        XCTAssertNil(focus(recorder.api(windowId: nil)).acquire(window: window))
        XCTAssertTrue(recorder.records.isEmpty)
    }

    func testRefusedFocusRecordStopsWithoutRelease() {
        let recorder = Recorder()
        recorder.failAt = 0
        XCTAssertNil(focus(recorder.api()).acquire(window: window))
        XCTAssertEqual(recorder.records.count, 1)
    }

    func testRefusedKeyRecordReleasesFocus() {
        for failAt in [1, 2] {
            let recorder = Recorder()
            recorder.failAt = failAt
            XCTAssertNil(focus(recorder.api()).acquire(window: window))
            XCTAssertEqual(recorder.records.last?[Fixture.focusStateOffset], Fixture.releaseState)
        }
    }

    func testReleaseTargetsTheAcquiredWindow() throws {
        let recorder = Recorder()
        try XCTUnwrap(focus(recorder.api()).acquire(window: window))()
        let release = try XCTUnwrap(recorder.records.last)
        XCTAssertEqual(Array(release[Fixture.windowOffset..<Fixture.windowOffset + Fixture.windowBytes.count]), Fixture.windowBytes)
    }
}

final class BackgroundImagePasteTests: XCTestCase {
    private enum Fixture {
        static let windowPid: pid_t = 501
        static let inputPid: pid_t = 502
        static let sheetPid: pid_t = 503
        static let buttonPid: pid_t = 504
        static let image = "/tmp/image.png"
        static let sendTitle = "1개 전송"
        static let acquire = "acquire"
        static let release = "release"
        static let write = "write"
        static let restore = "restore"
        static let focus = "focus"
        static let backgroundPaste = "backgroundPaste"
        static let activate = "activate"
        static let foregroundPaste = "foregroundPaste"
        static let confirm = "confirm"
    }

    private final class UI {
        let window = AXUIElementCreateApplication(Fixture.windowPid)
        let input = AXUIElementCreateApplication(Fixture.inputPid)
        let sheet = AXUIElementCreateApplication(Fixture.sheetPid)
        let button = AXUIElementCreateApplication(Fixture.buttonPid)
        var events: [String] = []
        var now = Date(timeIntervalSince1970: .zero)
        var sheetVisible = false
        var backgroundShowsSheet = true
        var focusAvailable = true
        var inputFocusable = true
        var sheetArrivesLate = false

        func dependencies() -> ImagePaste.Dependencies {
            var dependencies = ImagePaste.Dependencies()
            dependencies.acquireFocus = { _ in
                guard self.focusAvailable else { return nil }
                self.events.append(Fixture.acquire)
                return { self.events.append(Fixture.release) }
            }
            dependencies.pid = { _ in Fixture.windowPid }
            dependencies.focusInput = { _ in self.events.append(Fixture.focus); return self.inputFocusable }
            dependencies.pressPaste = { _ in
                self.events.append(Fixture.backgroundPaste)
                self.sheetVisible = self.backgroundShowsSheet
            }
            dependencies.captureFocus = { {} }
            dependencies.activate = {
                self.events.append(Fixture.activate)
                if self.sheetArrivesLate { self.sheetVisible = true }
            }
            dependencies.raise = { _ in }
            dependencies.click = { _ in }
            dependencies.readClipboard = { [] }
            dependencies.restoreClipboard = { _ in self.events.append(Fixture.restore) }
            dependencies.writeFiles = { _ in self.events.append(Fixture.write); return true }
            dependencies.paste = { self.events.append(Fixture.foregroundPaste); self.sheetVisible = true }
            dependencies.children = { element in
                if CFEqual(element, self.window) { return self.sheetVisible ? [self.sheet] : [] }
                return CFEqual(element, self.sheet) ? [self.button] : []
            }
            dependencies.role = { CFEqual($0, self.sheet) ? kAXSheetRole as String : kAXButtonRole as String }
            dependencies.title = { _ in Fixture.sendTitle }
            dependencies.press = { _ in self.events.append(Fixture.confirm); self.sheetVisible = false; return true }
            dependencies.sleep = { self.now.addTimeInterval($0) }
            dependencies.clock = { self.now }
            return dependencies
        }

        func send() throws -> ImageRoute? {
            try ImagePaste(dependencies: dependencies()).send(in: window, input: input, images: [Fixture.image])
        }
    }

    func testBackgroundPasteNeverActivatesAndReleasesBeforeConfirming() throws {
        let ui = UI()
        XCTAssertEqual(try ui.send(), .background)
        XCTAssertEqual(ui.events, [Fixture.acquire, Fixture.write, Fixture.focus, Fixture.backgroundPaste,
                                   Fixture.restore, Fixture.release, Fixture.confirm])
    }

    func testUnavailableFocusUsesForegroundPath() throws {
        let ui = UI()
        ui.focusAvailable = false
        XCTAssertEqual(try ui.send(), .foreground)
        XCTAssertTrue(ui.events.contains(Fixture.activate))
        XCTAssertFalse(ui.events.contains(Fixture.backgroundPaste))
    }

    func testMissingSheetReleasesFocusThenUsesForegroundPath() throws {
        let ui = UI()
        ui.backgroundShowsSheet = false
        XCTAssertEqual(try ui.send(), .foreground)
        let release = try XCTUnwrap(ui.events.firstIndex(of: Fixture.release))
        let activate = try XCTUnwrap(ui.events.firstIndex(of: Fixture.activate))
        let paste = try XCTUnwrap(ui.events.firstIndex(of: Fixture.foregroundPaste))
        let restore = try XCTUnwrap(ui.events.lastIndex(of: Fixture.restore))
        XCTAssertLessThan(release, activate)
        XCTAssertLessThan(paste, restore)
        XCTAssertEqual(ui.events.filter { $0 == Fixture.foregroundPaste }.count, 1)
    }

    func testUserClipboardStaysAwayUntilForegroundFallbackEnds() throws {
        let ui = UI()
        ui.backgroundShowsSheet = false
        _ = try ui.send()
        let activate = try XCTUnwrap(ui.events.firstIndex(of: Fixture.activate))
        XCTAssertFalse(ui.events[..<activate].contains(Fixture.restore))
    }

    func testLateBackgroundSheetIsNotPastedTwice() throws {
        let ui = UI()
        ui.backgroundShowsSheet = false
        ui.sheetArrivesLate = true
        _ = try ui.send()
        XCTAssertFalse(ui.events.contains(Fixture.foregroundPaste))
        XCTAssertEqual(ui.events.filter { $0 == Fixture.confirm }.count, 1)
        XCTAssertTrue(ui.events.contains(Fixture.restore))
    }

    func testUnfocusableInputReleasesFocusWithoutPressingPaste() throws {
        let ui = UI()
        ui.inputFocusable = false
        XCTAssertEqual(try ui.send(), .foreground)
        XCTAssertFalse(ui.events.contains(Fixture.backgroundPaste))
        XCTAssertTrue(ui.events.contains(Fixture.release))
        let release = try XCTUnwrap(ui.events.firstIndex(of: Fixture.release))
        XCTAssertTrue(ui.events[..<release].contains(Fixture.restore))
    }

    func testNoImagesHaveNoRoute() throws {
        let ui = UI()
        XCTAssertNil(try ImagePaste(dependencies: ui.dependencies()).send(in: ui.window, input: ui.input, images: []))
        XCTAssertTrue(ui.events.isEmpty)
    }
}

final class ImageRouteResultTests: XCTestCase {
    private enum Fixture {
        static let chatId: Int64 = 42
        static let logId: Int64 = 101
        static let pid: pid_t = 601
        static let title = "나와의 채팅"
        static let text = "text"
        static let image = "/tmp/image.png"
        static let routeKey = "imageRoute"
    }

    private func operation(route: ImageRoute?, outcome: SendVerifier.Outcome) -> SendOperation {
        SendOperation(dependencies: dependencies(route: route, outcome: outcome))
    }

    private func dependencies(route: ImageRoute?, outcome: SendVerifier.Outcome) -> SendOperation.Dependencies {
        var dependencies = SendOperation.Dependencies()
        dependencies.room = { _ in
            RoomRow(chatId: Fixture.chatId, type: KktConstants.selfRoomType, linkId: KktConstants.noLinkId,
                    linkUrl: nil, displayName: Fixture.title)
        }
        dependencies.open = { _ in AXUIElementCreateApplication(Fixture.pid) }
        dependencies.close = { _ in }
        dependencies.isWindowOpen = { _ in false }
        dependencies.children = { _ in [] }
        dependencies.inputState = { _ in .ready }
        dependencies.send = { _, _, _ in route }
        dependencies.verify = { _, _, _, _, _ in outcome }
        return dependencies
    }

    func testSentResultReportsImageRoute() throws {
        let result = try operation(route: .background, outcome: .sent(logId: Fixture.logId))
            .execute(chatId: Fixture.chatId, text: "", images: [Fixture.image], dryRun: false)
        XCTAssertEqual(result.imageRoute, ImageRoute.background.rawValue)
    }

    func testUncertainResultReportsImageRoute() throws {
        let result = try operation(route: .foreground, outcome: .uncertain)
            .execute(chatId: Fixture.chatId, text: "", images: [Fixture.image], dryRun: false)
        XCTAssertEqual(result.imageRoute, ImageRoute.foreground.rawValue)
    }

    func testUnclosedWindowResultKeepsImageRoute() throws {
        var dependencies = dependencies(route: .background, outcome: .sent(logId: Fixture.logId))
        dependencies.isWindowOpen = { _ in true }
        var now = Date(timeIntervalSince1970: .zero)
        dependencies.clock = { now }
        dependencies.sleep = { now.addTimeInterval($0) }
        let result = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: "", images: [Fixture.image], dryRun: false)
        XCTAssertEqual(result.result, KktConstants.uncertainResult)
        XCTAssertEqual(result.imageRoute, ImageRoute.background.rawValue)
    }

    func testTextOnlyResultOmitsImageRoute() throws {
        let result = try operation(route: nil, outcome: .sent(logId: Fixture.logId))
            .execute(chatId: Fixture.chatId, text: Fixture.text, images: [], dryRun: false)
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        XCTAssertFalse(json.contains(Fixture.routeKey))
    }
}
