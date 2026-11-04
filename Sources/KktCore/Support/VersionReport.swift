import AppKit

public struct VersionReport: Equatable {
    public let kakaoVersion: String?
    public let kakaoVerified: Bool
    public let macOSVersion: String
    public let executablePath: String
    public let homeDirectory: String

    public init(kakaoVersion: String?, kakaoVerified: Bool, macOSVersion: String, executablePath: String,
                homeDirectory: String) {
        self.kakaoVersion = kakaoVersion
        self.kakaoVerified = kakaoVerified
        self.macOSVersion = macOSVersion
        self.executablePath = executablePath
        self.homeDirectory = homeDirectory
    }

    public static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> VersionReport {
        let config = try? KktConfig.load(environment: environment)
        let kakao = NSWorkspace.shared.urlForApplication(withBundleIdentifier: KakaoApp.bundleId)
            .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: KktConstants.Doctor.bundleVersionKey) as? String }
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = [system.majorVersion, system.minorVersion, system.patchVersion].map(String.init)
            .joined(separator: KktConstants.Version.versionSeparator)
        return VersionReport(kakaoVersion: kakao,
                             kakaoVerified: kakao.map { config?.verifiedKakaoVersions.contains($0) == true } ?? false,
                             macOSVersion: macOS,
                             executablePath: Bundle.main.executableURL?.path ?? KktConstants.Doctor.executableFallback,
                             homeDirectory: NSHomeDirectory())
    }

    public var plain: String {
        KktConstants.commandName + KktConstants.Version.space + KktConstants.version
    }

    public func standardOutput(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        output(stdoutIsTerminal: isatty(STDOUT_FILENO) == KktConstants.Progress.isTerminal, environment: environment)
    }

    func output(stdoutIsTerminal: Bool, environment: [String: String]) -> String {
        guard stdoutIsTerminal else { return plain }
        let dumb = environment[KktConstants.Progress.termKey] == KktConstants.Progress.dumbTerm
        return banner(colored: ProgressIndicator.isColored(environment: environment) && !dumb)
    }

    func banner(colored: Bool) -> String {
        let style = { (text: String, code: String) in
            colored ? code + text + KktConstants.Progress.resetStyle : text
        }
        let row = { (icon: String, label: String, value: String) in
            let padding = KktConstants.Version.labelWidth - Self.displayWidth(label)
            return KktConstants.Version.indent + icon + KktConstants.Version.space
                + style(label, KktConstants.Progress.elapsedStyle)
                + String(repeating: KktConstants.Version.space, count: padding) + value
        }
        return [
            style(KktConstants.commandName, KktConstants.Version.nameStyle) + KktConstants.Version.space
                + style(KktConstants.version, KktConstants.Progress.labelStyle),
            style(KktConstants.Version.tagline, KktConstants.Progress.elapsedStyle),
            String(),
            row(KktConstants.Version.kakaoIcon, KktConstants.Version.kakaoLabel, kakaoStatus),
            row(KktConstants.Version.macOSIcon, KktConstants.Version.macOSLabel, macOSVersion),
            row(KktConstants.Version.executableIcon, KktConstants.Version.executableLabel, shortExecutablePath),
            String(),
            KktConstants.Version.indent + KktConstants.Version.homepageIcon + KktConstants.Version.space
                + style(KktConstants.Version.homepage, KktConstants.Progress.elapsedStyle),
        ].joined(separator: KktConstants.newline)
    }

    private var kakaoStatus: String {
        guard let kakaoVersion else { return KktConstants.Version.kakaoMissing }
        return kakaoVersion + (kakaoVerified ? KktConstants.Version.verified : KktConstants.Version.unverified)
    }

    private var shortExecutablePath: String {
        guard executablePath.hasPrefix(homeDirectory + KktConstants.Version.pathSeparator) else { return executablePath }
        return KktConstants.Version.homeMark + executablePath.dropFirst(homeDirectory.count)
    }

    private static func displayWidth(_ text: String) -> Int {
        text.unicodeScalars.reduce(.zero) {
            $0 + ($1.value >= KktConstants.Version.wideScalarStart ? KktConstants.Version.wideWidth
                : KktConstants.Version.narrowWidth)
        }
    }
}

extension KktConstants {
    public enum Version {
        public static let option = "version"
        public static let help = "Show the version."
        static let tagline = "macOS 카카오톡 CLI"
        static let homepage = "https://github.com/posth2071/kkt"
        static let kakaoLabel = "카카오톡"
        static let macOSLabel = "macOS"
        static let executableLabel = "실행 파일"
        static let kakaoIcon = "💬"
        static let macOSIcon = "💻"
        static let executableIcon = "📦"
        static let homepageIcon = "🔗"
        static let verified = " ✅ 검증됨"
        static let unverified = " ⚠️ 미검증"
        static let kakaoMissing = "찾을 수 없음"
        static let nameStyle = "\u{1B}[1;36m"
        static let indent = "  "
        static let space = " "
        static let versionSeparator = "."
        static let pathSeparator = "/"
        static let homeMark = "~"
        static let labelWidth = 11
        static let wideScalarStart: UInt32 = 0x1100
        static let wideWidth = 2
        static let narrowWidth = 1
    }
}
