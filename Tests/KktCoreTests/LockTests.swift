import Foundation
import XCTest
@testable import KktCore

final class LockTests: XCTestCase {
    func testLockExcludesOtherOwnersAndCanBeReacquired() throws {
        try withPath { path in
            let first = KktLock(path: path)
            let second = KktLock(path: path)
            try first.acquire(timeout: 0)
            XCTAssertNoThrow(try first.acquire(timeout: 0))
            XCTAssertThrowsError(try second.acquire(timeout: 0)) {
                XCTAssertEqual($0 as? KktError, .busy)
            }
            first.release()
            XCTAssertNoThrow(try second.acquire(timeout: 0))
            second.release()
            XCTAssertNoThrow(try first.acquire(timeout: 0))
            first.release()
        }
    }

    func testLockWaitUsesInjectedClockAndSleep() throws {
        try withPath { path in
            let first = KktLock(path: path)
            try first.acquire(timeout: 0)
            defer { first.release() }
            var now = TimeInterval.zero
            var sleeps: [TimeInterval] = []
            let second = KktLock(path: path, clock: { now }, sleep: {
                sleeps.append($0)
                now += $0
            })
            XCTAssertThrowsError(try second.acquire(timeout: 0.5)) {
                XCTAssertEqual($0 as? KktError, .busy)
            }
            XCTAssertEqual(now, 0.5)
            XCTAssertEqual(sleeps.reduce(0, +), 0.5)
        }
    }

    func testSendIntervalWaitsRemainder() throws {
        try withPath { path in
            let start = Date(timeIntervalSince1970: 100)
            var sleeps: [TimeInterval] = []
            try SendInterval(path: path, clock: { start }, sleep: { _ in }).record()
            let interval = SendInterval(path: path, clock: { start.addingTimeInterval(0.5) },
                                        sleep: { sleeps.append($0) })
            try interval.waitIfNeeded(minimum: 2.0)
            XCTAssertEqual(sleeps, [1.5])
        }
    }

    func testSendIntervalDoesNotWaitWithoutRecentRecord() throws {
        try withPath { path in
            var now = Date(timeIntervalSince1970: 100)
            var sleeps: [TimeInterval] = []
            let interval = SendInterval(path: path, clock: { now }, sleep: { sleeps.append($0) })
            try interval.waitIfNeeded()
            try interval.record()
            now.addTimeInterval(3)
            try interval.waitIfNeeded()
            XCTAssertEqual(sleeps, [])
            XCTAssertTrue(FileManager.default.fileExists(atPath: path + ".last-send"))
        }
    }

    private func withPath(_ body: (String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("kkt.lock").path)
    }
}
