import ApplicationServices
import XCTest
@testable import KktCore

final class UserWindowGuardTests: XCTestCase {
    func testGuardRejectsAnyNonMainWindow() throws {
        let main = WindowInfo(identifier: "Main Window", title: "카카오톡")
        let chat = WindowInfo(identifier: "AXWindow-123", title: "엄마")
        XCTAssertThrowsError(try UserWindowGuard.check(windows: [main, chat])) {
            XCTAssertEqual($0 as? KktError, .chatWindowOpen)
        }
        XCTAssertThrowsError(try UserWindowGuard.check(windows: [.init(identifier: nil, title: nil)])) {
            XCTAssertEqual($0 as? KktError, .chatWindowOpen)
        }
        XCTAssertNoThrow(try UserWindowGuard.check(windows: [main]))
        XCTAssertNoThrow(try UserWindowGuard.check(windows: []))
    }
}
