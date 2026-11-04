import ApplicationServices
import Foundation
@testable import KktCore
import XCTest

final class ProgressTests: XCTestCase {
    private enum Fixture {
        static let clearLine = "\r\u{1B}[2K"
        static let imageCount = 3
        static let label = "방 여는 중…"
        static let firstFrame = "⠋"
        static let secondFrame = "⠙"
        static let disableKey = "KKT_NO_PROGRESS"
        static let disableValue = "1"
        static let termKey = "TERM"
        static let dumbTerm = "dumb"
        static let normalTerm = "xterm-256color"
        static let noColorKey = "NO_COLOR"
        static let elapsed: TimeInterval = 3.2
        static let zeroElapsed = "0.0초"
        static let elapsedText = "3.2초"
        static let gap = "  "
        static let cyan = "\u{1B}[36m"
        static let bold = "\u{1B}[1m"
        static let dim = "\u{1B}[2m"
        static let reset = "\u{1B}[0m"
        static let realDelay: TimeInterval = 0.01
        static let realTimeout: TimeInterval = 2
    }

    private final class Harness: @unchecked Sendable {
        private let lock = NSLock()
        private var storedWrites: [String] = []
        private var storedTick: (@Sendable () -> Void)?
        private var storedCancels = 0
        private var storedNow = Date(timeIntervalSince1970: .zero)

        var writes: [String] { lock.withLock { storedWrites } }
        var cancels: Int { lock.withLock { storedCancels } }
        var scheduled: Bool { lock.withLock { storedTick != nil } }

        func indicator(enabled: Bool = true, colored: Bool = false) -> ProgressIndicator {
            ProgressIndicator(enabled: enabled, colored: colored, write: { [self] text in
                lock.withLock { storedWrites.append(text) }
            }, schedule: { [self] tick in
                lock.withLock { storedTick = tick }
                return { [self] in lock.withLock { storedCancels += 1 } }
            }, now: { [self] in lock.withLock { storedNow } })
        }

        func tick() { lock.withLock { storedTick }?() }
        func advance(_ seconds: TimeInterval) { lock.withLock { storedNow.addTimeInterval(seconds) } }
    }

    private struct Failure: Error {}

    private func line(_ frame: String, _ label: String, _ elapsed: String = Fixture.zeroElapsed) -> String {
        Fixture.clearLine + frame + " " + label + Fixture.gap + elapsed
    }

    func testShowsOnlyOnATerminalWithoutOptOut() {
        let normal = [Fixture.termKey: Fixture.normalTerm]
        XCTAssertTrue(ProgressIndicator.isEnabled(stderrIsTerminal: true, environment: normal, json: false))
        XCTAssertTrue(ProgressIndicator.isEnabled(stderrIsTerminal: true, environment: [:], json: false))
        XCTAssertFalse(ProgressIndicator.isEnabled(stderrIsTerminal: false, environment: normal, json: false))
        XCTAssertFalse(ProgressIndicator.isEnabled(stderrIsTerminal: true, environment: normal, json: true))
        XCTAssertFalse(ProgressIndicator.isEnabled(stderrIsTerminal: true,
                                                   environment: [Fixture.termKey: Fixture.dumbTerm], json: false))
        XCTAssertFalse(ProgressIndicator.isEnabled(stderrIsTerminal: true,
                                                   environment: [Fixture.disableKey: Fixture.disableValue], json: false))
    }

    func testAnEmptyOptOutValueKeepsTheIndicatorOn() {
        XCTAssertTrue(ProgressIndicator.isEnabled(stderrIsTerminal: true,
                                                  environment: [Fixture.disableKey: String()], json: false))
    }

    func testDisabledIndicatorNeverSchedulesOrWrites() {
        let harness = Harness()
        let indicator = harness.indicator(enabled: false)

        indicator.update(.openingRoom)
        indicator.stop()

        XCTAssertFalse(harness.scheduled)
        XCTAssertEqual(harness.writes, [])
    }

    func testCommandFinishedBeforeTheFirstTickLeavesNoOutput() {
        let harness = Harness()
        let indicator = harness.indicator()

        indicator.update(.openingRoom)
        indicator.stop()

        XCTAssertEqual(harness.writes, [])
        XCTAssertEqual(harness.cancels, 1)
    }

    func testTicksAdvanceTheFrameOnOneLine() {
        let harness = Harness()
        let indicator = harness.indicator()

        indicator.update(.openingRoom)
        harness.tick()
        harness.tick()

        XCTAssertEqual(harness.writes, [line(Fixture.firstFrame, Fixture.label), line(Fixture.secondFrame, Fixture.label)])
    }

    func testVisibleIndicatorRedrawsAtOnceWhenTheStageChanges() {
        let harness = Harness()
        let indicator = harness.indicator()

        indicator.update(.openingRoom)
        harness.tick()
        indicator.update(.verifying)

        XCTAssertEqual(harness.writes.last, line(Fixture.firstFrame, ProgressStage.verifying.label))
    }

    func testStopClearsTheLineAndIgnoresALateTick() {
        let harness = Harness()
        let indicator = harness.indicator()

        indicator.update(.openingRoom)
        harness.tick()
        indicator.stop()
        harness.tick()

        XCTAssertEqual(harness.writes.last, Fixture.clearLine)
        XCTAssertEqual(harness.writes.count, 2)
    }

    func testDuringStopsBeforeReturningTheResult() {
        let harness = Harness()
        let indicator = harness.indicator()

        let value = indicator.during(.joining) { () -> [String] in
            harness.tick()
            return harness.writes
        }

        XCTAssertEqual(value.count, 1)
        XCTAssertEqual(harness.writes.last, Fixture.clearLine)
    }

    func testDuringStopsWhenTheBodyThrows() {
        let harness = Harness()
        let indicator = harness.indicator()

        XCTAssertThrowsError(try indicator.during(.joining) {
            harness.tick()
            throw Failure()
        })

        XCTAssertEqual(harness.writes.last, Fixture.clearLine)
    }

    func testIndicatorCanRunAgainAfterStopping() {
        let harness = Harness()
        let indicator = harness.indicator()

        indicator.during(.readingNotice) {}
        indicator.update(.readingNotice)
        harness.tick()

        XCTAssertEqual(harness.writes, [line(Fixture.firstFrame, ProgressStage.readingNotice.label)])
    }

    func testElapsedTimeCountsFromTheFirstStage() {
        let harness = Harness()
        let indicator = harness.indicator()

        indicator.update(.openingRoom)
        harness.advance(Fixture.elapsed)
        indicator.update(.verifying)
        harness.tick()

        XCTAssertEqual(harness.writes, [line(Fixture.firstFrame, ProgressStage.verifying.label, Fixture.elapsedText)])
    }

    func testElapsedTimeRestartsAfterStopping() {
        let harness = Harness()
        let indicator = harness.indicator()

        indicator.during(.readingNotice) { harness.advance(Fixture.elapsed) }
        indicator.update(.readingNotice)
        harness.tick()

        XCTAssertEqual(harness.writes, [line(Fixture.firstFrame, ProgressStage.readingNotice.label)])
    }

    func testColoredLineStylesEachPart() {
        let harness = Harness()
        let indicator = harness.indicator(colored: true)

        indicator.update(.openingRoom)
        harness.advance(Fixture.elapsed)
        harness.tick()

        XCTAssertEqual(harness.writes, [
            Fixture.clearLine + Fixture.cyan + Fixture.firstFrame + Fixture.reset + " "
                + Fixture.bold + Fixture.label + Fixture.reset + Fixture.gap
                + Fixture.dim + Fixture.elapsedText + Fixture.reset,
        ])
    }

    func testNoColorTurnsOffStylingOnly() {
        XCTAssertTrue(ProgressIndicator.isColored(environment: [:]))
        XCTAssertTrue(ProgressIndicator.isColored(environment: [Fixture.noColorKey: String()]))
        XCTAssertFalse(ProgressIndicator.isColored(environment: [Fixture.noColorKey: Fixture.disableValue]))
        XCTAssertTrue(ProgressIndicator.isEnabled(stderrIsTerminal: true,
                                                  environment: [Fixture.noColorKey: Fixture.disableValue], json: false))
    }

    func testImageStageNamesTheCount() {
        XCTAssertTrue(ProgressStage.pastingImages(Fixture.imageCount).label.contains(String(Fixture.imageCount)))
    }

    func testRealTimerDrawsAfterItsDelay() {
        let drawn = expectation(description: "drawn")
        drawn.assertForOverFulfill = false
        let indicator = ProgressIndicator(enabled: true, colored: false, write: { _ in drawn.fulfill() },
                                          schedule: ProgressIndicator.timer(delay: Fixture.realDelay,
                                                                            interval: Fixture.realDelay))

        indicator.update(.openingRoom)
        wait(for: [drawn], timeout: Fixture.realTimeout)
        indicator.stop()
    }
}

final class SendProgressTests: XCTestCase {
    private enum Fixture {
        static let chatId: Int64 = 42
        static let logId: Int64 = 101
        static let pid: pid_t = 601
        static let title = "나와의 채팅"
        static let text = "text"
        static let images = ["/tmp/a.png", "/tmp/b.png"]
    }

    private func stages(text: String, images: [String], dryRun: Bool = false) throws -> [ProgressStage] {
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
        dependencies.send = { _, _, _ in nil }
        dependencies.verify = { _, _, _, _, _ in .sent(logId: Fixture.logId) }
        var seen: [ProgressStage] = []
        _ = try SendOperation(dependencies: dependencies)
            .execute(chatId: Fixture.chatId, text: text, images: images, dryRun: dryRun, progress: { seen.append($0) })
        return seen
    }

    func testTextSendReportsEachStage() throws {
        XCTAssertEqual(try stages(text: Fixture.text, images: []), [.openingRoom, .sending, .verifying])
    }

    func testImageSendReportsTheImageCount() throws {
        XCTAssertEqual(try stages(text: Fixture.text, images: Fixture.images),
                       [.openingRoom, .pastingImages(Fixture.images.count), .verifying])
    }

    func testDryRunStopsAfterOpeningTheRoom() throws {
        XCTAssertEqual(try stages(text: Fixture.text, images: [], dryRun: true), [.openingRoom])
    }
}
