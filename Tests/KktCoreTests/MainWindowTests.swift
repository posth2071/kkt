import ApplicationServices
import XCTest
@testable import KktCore

private enum Fixture {
    static let pid: pid_t = 701
    static var app: AXUIElement { AXUIElementCreateApplication(700) }
    static var main: AXUIElement { AXUIElementCreateApplication(701) }
    static let failure = "failure"
}

final class MainWindowOpeningTests: XCTestCase {
    private final class UI {
        var windows: [AXUIElement] = []
        var minimized = false
        var menuWorks = true
        var menuPresses = 0
        var reopens = 0
        var restores = 0
        var now = Date(timeIntervalSince1970: .zero)

        func dependencies() -> ChatOpener.Dependencies {
            var dependencies = ChatOpener.Dependencies()
            dependencies.frontmostBundleId = { nil }
            dependencies.runningPid = { Fixture.pid }
            dependencies.appElement = { _ in Fixture.app }
            dependencies.windows = { _ in self.windows }
            dependencies.identifier = { CFEqual($0, Fixture.main) ? KktConstants.mainWindowIdentifier : nil }
            dependencies.isMinimized = { _ in self.minimized }
            dependencies.showMainWindow = { _ in
                self.menuPresses += 1
                guard self.menuWorks else { return false }
                self.windows = [Fixture.main]
                self.minimized = false
                return true
            }
            dependencies.reopen = { self.reopens += 1; self.windows = [Fixture.main]; self.minimized = false }
            dependencies.captureFocus = { { self.restores += 1 } }
            dependencies.sleep = { self.now.addTimeInterval($0) }
            dependencies.clock = { self.now }
            return dependencies
        }

        func prepare() throws -> AXUIElement {
            try ChatOpener.prepareWindows(dependencies: dependencies()).mainWindow
        }
    }

    func testOpenMainWindowDoesNotTouchTheMenu() throws {
        let ui = UI()
        ui.windows = [Fixture.main]
        XCTAssertTrue(CFEqual(try ui.prepare(), Fixture.main))
        XCTAssertEqual(ui.menuPresses, 0)
        XCTAssertEqual(ui.reopens, 0)
    }

    func testMinimizedMainWindowIsRestoredByTheMenu() throws {
        let ui = UI()
        ui.windows = [Fixture.main]
        ui.minimized = true
        XCTAssertTrue(CFEqual(try ui.prepare(), Fixture.main))
        XCTAssertEqual(ui.menuPresses, 1)
        XCTAssertFalse(ui.minimized)
        XCTAssertEqual(ui.reopens, 0)
    }

    func testClosedMainWindowOpensByTheMenuWithoutReopeningTheApp() throws {
        let ui = UI()
        XCTAssertTrue(CFEqual(try ui.prepare(), Fixture.main))
        XCTAssertEqual(ui.menuPresses, 1)
        XCTAssertEqual(ui.reopens, 0)
        XCTAssertEqual(ui.restores, 0)
    }

    func testClosedMainWindowFallsBackToReopenWhenTheMenuIsMissing() throws {
        let ui = UI()
        ui.menuWorks = false
        XCTAssertTrue(CFEqual(try ui.prepare(), Fixture.main))
        XCTAssertEqual(ui.reopens, 1)
    }

    func testMinimizedMainWindowFallsBackToReopenWhenTheMenuIsMissing() throws {
        let ui = UI()
        ui.windows = [Fixture.main]
        ui.minimized = true
        ui.menuWorks = false
        XCTAssertTrue(CFEqual(try ui.prepare(), Fixture.main))
        XCTAssertEqual(ui.reopens, 1)
        XCTAssertFalse(ui.minimized)
    }

    func testClosedMainWindowFallsBackToReopenWhenTheMenuShowsNothing() throws {
        let ui = UI()
        var dependencies = ui.dependencies()
        dependencies.showMainWindow = { _ in true }
        XCTAssertTrue(CFEqual(try ChatOpener.prepareWindows(dependencies: dependencies).mainWindow, Fixture.main))
        XCTAssertEqual(ui.reopens, 1)
        XCTAssertGreaterThanOrEqual(ui.now.timeIntervalSince1970, KktConstants.mainWindowMenuTimeout)
    }
}

final class MainWindowKeeperTests: XCTestCase {
    private final class UI {
        var windows: [AXUIElement] = []
        var readable = true
        var minimized = false
        var closes = 0
        var minimizes = 0

        var keeper: MainWindowKeeper {
            var dependencies = MainWindowKeeper.Dependencies()
            dependencies.runningPid = { Fixture.pid }
            dependencies.appElement = { _ in Fixture.app }
            dependencies.windows = { _ in self.readable ? self.windows : nil }
            dependencies.identifier = { CFEqual($0, Fixture.main) ? KktConstants.mainWindowIdentifier : nil }
            dependencies.isMinimized = { _ in self.minimized }
            dependencies.close = { _ in self.closes += 1 }
            dependencies.minimize = { _ in self.minimizes += 1 }
            return MainWindowKeeper(dependencies: dependencies)
        }

        func show() { windows = [Fixture.main]; minimized = false }
    }

    func testClosedWindowIsClosedAgain() {
        let ui = UI()
        ui.keeper.preserving { ui.show() }
        XCTAssertEqual(ui.closes, 1)
        XCTAssertEqual(ui.minimizes, 0)
    }

    func testMinimizedWindowIsMinimizedAgain() {
        let ui = UI()
        ui.windows = [Fixture.main]
        ui.minimized = true
        ui.keeper.preserving { ui.show() }
        XCTAssertEqual(ui.minimizes, 1)
        XCTAssertEqual(ui.closes, 0)
    }

    func testOpenWindowIsLeftAlone() {
        let ui = UI()
        ui.show()
        ui.keeper.preserving {}
        XCTAssertEqual(ui.closes + ui.minimizes, 0)
    }

    func testWindowThatWasNeverShownIsLeftAlone() {
        let ui = UI()
        ui.keeper.preserving {}
        XCTAssertEqual(ui.closes + ui.minimizes, 0)
    }

    func testUnreadableWindowListNeverClosesTheWindow() {
        let ui = UI()
        ui.readable = false
        ui.keeper.preserving {
            ui.readable = true
            ui.show()
        }
        XCTAssertEqual(ui.closes + ui.minimizes, 0)
    }

    func testWindowMinimizedDuringTheWorkIsNotClosed() {
        let ui = UI()
        ui.keeper.preserving {
            ui.show()
            ui.minimized = true
        }
        XCTAssertEqual(ui.closes, 0)
    }

    func testFailedWorkStillRestoresAndRethrows() {
        let ui = UI()
        XCTAssertThrowsError(try ui.keeper.preserving {
            ui.show()
            throw KktError.automation(Fixture.failure)
        })
        XCTAssertEqual(ui.closes, 1)
    }

    func testResultPassesThrough() {
        let ui = UI()
        ui.show()
        XCTAssertEqual(ui.keeper.preserving { Fixture.failure }, Fixture.failure)
    }

    func testKakaoTalkNotRunningRunsTheWorkWithoutRestoring() {
        let ui = UI()
        var dependencies = MainWindowKeeper.Dependencies()
        dependencies.runningPid = { nil }
        dependencies.close = { _ in ui.closes += 1 }
        var ran = false
        MainWindowKeeper(dependencies: dependencies).preserving { ran = true }
        XCTAssertTrue(ran)
        XCTAssertEqual(ui.closes, 0)
    }
}
