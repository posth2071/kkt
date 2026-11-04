@testable import KktCore
import XCTest

final class VersionReportTests: XCTestCase {
    private enum Fixture {
        static let kakao = "26.9.0"
        static let macOS = "27.0.1"
        static let home = "/Users/example"
        static let executable = "/Users/example/.local/bin/kkt"
        static let otherExecutable = "/opt/tools/kkt"
        static let shortExecutable = "~/.local/bin/kkt"
        static let verifiedLine = "  💬 카카오톡   26.9.0 ✅ 검증됨"
        static let unverifiedLine = "  💬 카카오톡   26.9.0 ⚠️ 미검증"
        static let missingLine = "  💬 카카오톡   찾을 수 없음"
        static let macOSLine = "  💻 macOS      27.0.1"
        static let executableLine = "  📦 실행 파일  ~/.local/bin/kkt"
        static let homepageLine = "  🔗 https://github.com/posth2071/kkt"
        static let escape = "\u{1B}["
        static let cyanBold = "\u{1B}[1;36mkkt\u{1B}[0m"
        static let dimLabel = "\u{1B}[2m카카오톡\u{1B}[0m"
        static let noColorKey = "NO_COLOR"
        static let termKey = "TERM"
        static let dumbTerm = "dumb"
        static let flagValue = "1"
    }

    private func report(kakao: String? = Fixture.kakao, verified: Bool = true,
                        executable: String = Fixture.executable) -> VersionReport {
        VersionReport(kakaoVersion: kakao, kakaoVerified: verified, macOSVersion: Fixture.macOS,
                      executablePath: executable, homeDirectory: Fixture.home)
    }

    private func lines(_ report: VersionReport) -> [String] {
        report.banner(colored: false).components(separatedBy: KktConstants.newline)
    }

    func testPlainLineIsTheNameAndVersionForScripts() {
        XCTAssertEqual(report().plain, KktConstants.commandName + " " + KktConstants.version)
    }

    func testBannerStartsWithThePlainLine() {
        XCTAssertEqual(lines(report()).first, report().plain)
    }

    func testBannerAlignsTheEnvironmentRows() {
        let rows = lines(report())
        XCTAssertTrue(rows.contains(Fixture.verifiedLine))
        XCTAssertTrue(rows.contains(Fixture.macOSLine))
        XCTAssertTrue(rows.contains(Fixture.executableLine))
        XCTAssertTrue(rows.contains(Fixture.homepageLine))
    }

    func testBannerMarksAnUnverifiedKakaoTalk() {
        XCTAssertTrue(lines(report(verified: false)).contains(Fixture.unverifiedLine))
    }

    func testBannerSaysWhenKakaoTalkIsMissing() {
        XCTAssertTrue(lines(report(kakao: nil, verified: false)).contains(Fixture.missingLine))
    }

    func testPathOutsideHomeStaysAbsolute() {
        XCTAssertTrue(report(executable: Fixture.otherExecutable).banner(colored: false)
            .contains(Fixture.otherExecutable))
    }

    func testPlainBannerHasNoEscapes() {
        XCTAssertFalse(report().banner(colored: false).contains(Fixture.escape))
    }

    func testColoredBannerStylesTheNameAndLabels() {
        let banner = report().banner(colored: true)
        XCTAssertTrue(banner.hasPrefix(Fixture.cyanBold))
        XCTAssertTrue(banner.contains(Fixture.dimLabel))
    }

    func testOutputFollowsTheTerminalAndColorSettings() {
        let plain = report().plain
        XCTAssertEqual(report().output(stdoutIsTerminal: false, environment: [:]), plain)
        XCTAssertEqual(report().output(stdoutIsTerminal: true, environment: [:]), report().banner(colored: true))
        XCTAssertEqual(report().output(stdoutIsTerminal: true, environment: [Fixture.noColorKey: Fixture.flagValue]),
                       report().banner(colored: false))
        XCTAssertEqual(report().output(stdoutIsTerminal: true, environment: [Fixture.termKey: Fixture.dumbTerm]),
                       report().banner(colored: false))
    }
}
