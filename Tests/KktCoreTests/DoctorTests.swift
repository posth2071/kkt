import Darwin
import Foundation
import XCTest
@testable import KktCore

final class DoctorTests: XCTestCase {
    private enum Fixture {
        static let version = "26.9.0"
        static let unverifiedVersion = "27.0.0"
        static let executable = "/test/bin/kkt"
        static let pid: pid_t = 42
        static let userId = 12345
        static let main = WindowInfo(identifier: "Main Window", title: "카카오톡")
    }

    func testFailsWhenAccessibilityMissing() throws {
        var probes = healthyProbes()
        probes.accessibility = { false }
        var uiCalls = 0
        probes.ui = { _ in uiCalls += 1; return .init(windows: [], elements: []) }
        let report = run(probes)
        let check = try check("accessibility", in: report)
        XCTAssertEqual(check.status, .fail)
        XCTAssertNotNil(check.fix)
        XCTAssertEqual(uiCalls, 0)
        XCTAssertEqual(report.exitCode, 1)
    }

    func testWarnsOnUnverifiedKakaoVersion() throws {
        var probes = healthyProbes()
        probes.version = { _ in Fixture.unverifiedVersion }
        let check = try check("kakaotalk_version", in: run(probes))
        XCTAssertEqual(check.status, .warn)
        XCTAssertTrue(check.detail.contains(Fixture.unverifiedVersion))
        XCTAssertNotNil(check.fix)
        XCTAssertEqual(try self.check("kakaotalk_version", in: run(healthyProbes())).status, .ok)
    }

    func testAxIdentifierTableReportsMissingIds() throws {
        var probes = healthyProbes()
        probes.ui = { _ in
            .init(windows: [Fixture.main], elements: self.mainElements().filter {
                $0.identifier != "chatrooms" && $0.identifier != "_NS:40"
            })
        }
        let check = try check("ax_identifiers", in: run(probes))
        XCTAssertEqual(check.status, .warn)
        XCTAssertTrue(check.detail.contains("chatrooms"))
        XCTAssertTrue(check.detail.contains("_NS:40"))
        XCTAssertFalse(check.detail.contains("_NS:51"))
        XCTAssertEqual(try self.check("ax_identifiers", in: run(healthyProbes())).status, .ok)
    }

    func testMissingBackgroundImagePathWarnsButKeepsForegroundFallback() throws {
        var probes = healthyProbes()
        probes.backgroundImage = { false }
        let check = try check("image_background", in: run(probes))
        XCTAssertEqual(check.status, .warn)
        XCTAssertNotNil(check.fix)
    }

    func testAvailableBackgroundImagePathIsOk() throws {
        var probes = healthyProbes()
        probes.backgroundImage = { true }
        XCTAssertEqual(try check("image_background", in: run(probes)).status, .ok)
    }

    func testUserWindowsCountsNonMainWindows() throws {
        let windows = [Fixture.main, WindowInfo(identifier: "_NS:443", title: "엄마"),
                       WindowInfo(identifier: nil, title: "설정"),
                       WindowInfo(identifier: "_NS:17", title: nil)]
        var probes = healthyProbes()
        probes.ui = { _ in .init(windows: windows, elements: self.mainElements()) }
        let check = try check("user_windows", in: run(probes))
        XCTAssertEqual(check.status, .warn)
        XCTAssertTrue(check.detail.contains("3"))
        XCTAssertNotNil(check.fix)
        let mainOnly = try self.check("user_windows", in: run(healthyProbes()))
        XCTAssertEqual(mainOnly.status, .ok)
        XCTAssertTrue(mainOnly.detail.contains("0"))
    }

    func testExitCodeOneOnAnyFail() {
        for status in [DoctorCheck.Status.ok, .warn, .fail] {
            let report = DoctorReport(executablePath: Fixture.executable, checks: [
                DoctorCheck(id: "first", status: .ok, detail: "ready", fix: nil),
                DoctorCheck(id: "last", status: status, detail: "probe", fix: nil),
            ])
            XCTAssertEqual(report.exitCode, status == .fail ? 1 : 0)
        }
        XCTAssertEqual(run(healthyProbes()).exitCode, 0)
    }

    func testAllChecksUseInjectedProbesAndIncludeExecutionContext() throws {
        let report = run(healthyProbes())
        XCTAssertEqual(report.checks.map(\.id), [
            "full_disk_access", "accessibility", "screen_recording", "sqlcipher", "user_id", "database_key",
            "kakaotalk_running", "kakaotalk_version", "main_window", "ax_identifiers", "lock", "user_windows",
            "kakaotalk_frontmost", "image_background",
        ])
        XCTAssertTrue(report.checks.allSatisfy { $0.status == .ok })
        XCTAssertTrue(report.humanOutput.components(separatedBy: "\n")[0].contains(Fixture.executable))
        XCTAssertTrue(report.humanOutput.contains("터미널/node"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(KktOutput.line(report).utf8)) as? [String: Any])
        XCTAssertEqual(json["executablePath"] as? String, Fixture.executable)
        XCTAssertTrue((json["permissionNote"] as? String)?.contains("터미널/node") == true)
        XCTAssertEqual((json["checks"] as? [[String: Any]])?.count, 14)
    }

    func testFrontmostIsInformationalEvenWhenKakaoTalkIsInUse() throws {
        var probes = healthyProbes()
        probes.frontmost = { true }
        let check = try check("kakaotalk_frontmost", in: run(probes))
        XCTAssertEqual(check.status, .ok)
        XCTAssertTrue(check.detail.contains("true"))
        XCTAssertNil(check.fix)
        XCTAssertEqual(run(probes).exitCode, 0)
    }

    func testPermissionDatabaseAndLockFailuresHaveFixes() throws {
        var probes = healthyProbes()
        probes.fullDiskAccess = { .denied }
        probes.screenRecording = { false }
        probes.sqlcipher = { nil }
        probes.lock = { _ in .busy }
        probes.databaseKey = { XCTFail("Unavailable database must not be opened"); return false }
        let report = run(probes)
        for id in ["full_disk_access", "screen_recording", "sqlcipher"] {
            XCTAssertEqual(try check(id, in: report).status, .fail)
            XCTAssertNotNil(try check(id, in: report).fix)
        }
        XCTAssertEqual(try check("database_key", in: report).status, .warn)
        XCTAssertEqual(try check("lock", in: report).status, .warn)
        probes = healthyProbes()
        probes.databaseKey = { false }
        XCTAssertEqual(try check("database_key", in: run(probes)).status, .fail)
        let noUser = DoctorChecks(config: KktConfig(), probes: healthyProbes()).run(executablePath: Fixture.executable)
        XCTAssertEqual(try check("user_id", in: noUser).status, .fail)
    }

    func testNotRunningSkipsUIAndReportsMissingMainWindow() throws {
        var probes = healthyProbes()
        probes.runningPid = { nil }
        probes.ui = { _ in XCTFail("Stopped app must not be queried"); return .init(windows: [], elements: []) }
        probes.version = { _ in XCTFail("No running app version"); return nil }
        let report = run(probes)
        XCTAssertEqual(try check("kakaotalk_running", in: report).status, .fail)
        XCTAssertEqual(try check("main_window", in: report).status, .warn)
        XCTAssertEqual(try check("user_windows", in: report).status, .warn)
    }

    func testAxTableMatchesDocumentedRolesAndVisibleContexts() {
        let elements = mainElements() + [
            .init(role: "AXWindow", identifier: "_NS:443"),
            .init(role: "AXScrollArea", identifier: "_NS:29"),
            .init(role: "AXTable", identifier: "_NS:33"),
            .init(role: "AXStaticText", identifier: "_NS:144"),
            .init(role: "AXScrollArea", identifier: "_NS:47"),
            .init(role: "AXTextArea", identifier: "_NS:51", description: "메시지 입력"),
            .init(role: "AXButton", title: "전송"),
            .init(role: "AXButton", title: "대화상대 2명"),
            .init(role: "AXImage", identifier: "_NS:98"),
        ]
        let snapshot = AXIdentifierTable.Snapshot(windows: [Fixture.main], elements: elements)
        XCTAssertEqual(AXIdentifierTable.missing(in: snapshot), [])
        let wrongRole = elements.filter { $0.identifier != "_NS:51" }
            + [AXIdentifierTable.Element(role: "AXTextField", identifier: "_NS:51")]
        XCTAssertTrue(AXIdentifierTable.missing(in: .init(windows: [Fixture.main], elements: wrongRole))
            .contains("_NS:51"))
    }

    func testLockProbeDoesNotCreateFilesAndDetectsHeldLock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("kkt.lock").path
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(DoctorChecks.lockState(path: path), .available)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        let lock = KktLock(path: path)
        try lock.acquire(timeout: 0)
        XCTAssertEqual(DoctorChecks.lockState(path: path), .busy)
        lock.release()
        XCTAssertEqual(DoctorChecks.lockState(path: path), .available)
    }

    func testHumanDoctorOutputKeepsAllMissingIdsAndFullFix() {
        let missing = "friends, chatrooms, more, _NS:63, _NS:40, Count Label, _NS:69, _NS:18, _NS:11"
        let fix = "시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근에서 실행 프로그램을 허용하세요."
        let report = DoctorReport(executablePath: Fixture.executable, checks: [
            .init(id: "ax_identifiers", status: .warn, detail: missing, fix: fix),
        ])
        XCTAssertTrue(report.humanOutput.contains(missing))
        XCTAssertTrue(report.humanOutput.contains(fix))
    }

    func testUnavailableWindowProbeDoesNotClaimZeroUserWindows() throws {
        var probes = healthyProbes()
        probes.ui = { _ in nil }
        let check = try check("user_windows", in: run(probes))
        XCTAssertEqual(check.status, .warn)
        XCTAssertFalse(check.detail.contains("0"))
    }

    func testSqlcipherProbeUsesLinkedLibraryWithoutOpeningRealDatabase() throws {
        XCTAssertFalse(try XCTUnwrap(DoctorChecks.cipherVersion()).isEmpty)
    }

    private func run(_ probes: DoctorChecks.Probes) -> DoctorReport {
        DoctorChecks(config: .init(userId: Fixture.userId, verifiedKakaoVersions: [Fixture.version]), probes: probes)
            .run(executablePath: Fixture.executable)
    }

    private func check(_ id: String, in report: DoctorReport) throws -> DoctorCheck {
        try XCTUnwrap(report.checks.first { $0.id == id })
    }

    private func healthyProbes() -> DoctorChecks.Probes {
        .init(fullDiskAccess: { .readable }, accessibility: { true }, screenRecording: { true },
              sqlcipher: { "4.6.1" }, databaseKey: { true }, runningPid: { Fixture.pid },
              version: { _ in Fixture.version }, ui: { _ in .init(windows: [Fixture.main], elements: self.mainElements()) },
              lock: { _ in .available }, frontmost: { false })
    }

    private func mainElements() -> [AXIdentifierTable.Element] {
        [
            .init(role: "AXWindow", identifier: "Main Window"),
            .init(role: "AXButton", identifier: "friends"),
            .init(role: "AXButton", identifier: "chatrooms"),
            .init(role: "AXButton", identifier: "more"),
            .init(role: "AXTable", identifier: "_NS:63"),
            .init(role: "AXRow"),
            .init(role: "AXStaticText", identifier: "_NS:40"),
            .init(role: "AXStaticText", identifier: "Count Label"),
            .init(role: "AXStaticText", identifier: "_NS:69"),
            .init(role: "AXImage", identifier: "_NS:18"),
            .init(role: "AXButton", identifier: "_NS:11"),
            .init(role: "AXButton", description: "검색"),
        ]
    }
}
