import Foundation

public struct DoctorCheck: Encodable, Equatable, Sendable {
    public enum Status: String, Encodable, Sendable { case ok, warn, fail }

    public let id: String
    public let status: Status
    public let detail: String
    public let fix: String?

    public init(id: String, status: Status, detail: String, fix: String? = nil) {
        self.id = id
        self.status = status
        self.detail = detail
        self.fix = fix
    }
}

public struct DoctorReport: Encodable {
    public let executablePath: String
    public let permissionNote = KktConstants.Doctor.permissionNote
    public let checks: [DoctorCheck]

    public init(executablePath: String, checks: [DoctorCheck]) {
        self.executablePath = executablePath
        self.checks = checks
    }

    public var exitCode: Int32 {
        checks.contains { $0.status == .fail } ? KktConstants.failureExitCode : KktConstants.successExitCode
    }

    public var humanOutput: String {
        let rows = checks.map { [$0.id, $0.status.rawValue, $0.detail, $0.fix ?? KktConstants.emptyText] }
        return KktConstants.Doctor.executablePrefix + executablePath + KktConstants.newline
            + permissionNote + KktConstants.newline
            + TableOutput.render(columns: KktConstants.Doctor.columns, rows: rows, truncate: false)
    }
}

extension KktConstants {
    public enum Doctor {
        public static let command = "doctor"
        public static let description = "권한, 데이터베이스와 카카오톡 UI 상태를 진단합니다."
        public static let permissionNote = "권한은 실행한 프로그램(터미널/node) 기준입니다. launchd에서 node로 실행하면 터미널과 권한 주체가 다릅니다."
        public static let executableFallback = "kkt"
        static let executablePrefix = "실행 파일: "
        static let columns = ["검사", "상태", "상세", "해결 방법"]
        static let fullDiskAccess = "full_disk_access"
        static let accessibility = "accessibility"
        static let screenRecording = "screen_recording"
        static let sqlcipher = "sqlcipher"
        static let userId = "user_id"
        static let databaseKey = "database_key"
        static let running = "kakaotalk_running"
        static let version = "kakaotalk_version"
        static let mainWindow = "main_window"
        static let axIdentifiers = "ax_identifiers"
        static let lock = "lock"
        static let userWindows = "user_windows"
        static let frontmost = "kakaotalk_frontmost"
        static let imageBackground = "image_background"
        static let imageBackgroundAvailable = "사진 백그라운드 경로 사용 가능"
        static let imageBackgroundMissing = "SkyLight 심볼이 없어 사진은 전면 경로로 보냅니다."
        static let imageBackgroundFix = "macOS 업데이트로 비공개 API가 바뀌었는지 docs/re/2026-11-03-kakaotalk-26.9.md 와 비교하세요."
        static let diskFix = "시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근에서 실행 프로그램을 허용하세요."
        static let accessibilityFix = "시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 실행 프로그램을 허용하세요."
        static let screenFix = "시스템 설정 > 개인정보 보호 및 보안 > 화면 기록에서 실행 프로그램을 허용하세요."
        static let sqlcipherFix = "brew install sqlcipher 후 kkt를 다시 빌드하세요."
        static let userFix = "설정과 KKT_USER_ID를 확인하고 kkt auth를 실행하세요."
        static let databaseFix = "DB 접근 권한과 계정을 확인하고 kkt auth로 키를 검증하세요."
        static let runningFix = "카카오톡을 실행하고 로그인하세요."
        static let versionFix = "현재 버전의 동작 검증 후 config.json의 verifiedKakaoVersions에 추가하세요."
        static let mainWindowFix = "카카오톡의 메인 창을 열어 주세요."
        static let axFix = "채팅 탭을 표시하고 docs/re/2026-11-03-kakaotalk-26.9.md 3절과 비교하세요."
        static let lockBusyFix = "다른 kkt 작업이 끝날 때까지 기다리세요."
        static let lockFix = "설정의 lockPath와 잠금 파일 접근 권한을 확인하세요."
        static let userWindowsFix = "메인 창 외 카카오톡 창을 닫아 주세요. 자동화는 그동안 대기합니다."
        static let readable = "DB 파일 읽기 가능"
        static let missingDatabase = "로컬 DB 없음: 전체 디스크 접근 확인 불가"
        static let denied = "DB 파일 접근 불가"
        static let granted = "허용됨"
        static let notGranted = "허용되지 않음"
        static let missingSQLCipher = "SQLCipher 라이브러리 확인 불가"
        static let userConfigured = "사용자 ID 설정됨"
        static let userMissing = "유효한 사용자 ID 설정 없음"
        static let keyValid = "읽기 전용 DB 열기 및 키 검증 성공"
        static let keyInvalid = "읽기 전용 DB 열기 또는 키 검증 실패"
        static let keySkipped = "DB 접근, SQLCipher 또는 사용자 ID 미확인: 키 검증 생략"
        static let isRunning = "실행 중"
        static let notRunning = "kakaotalk_not_running"
        static let unknownVersion = "실행 중인 카카오톡 버전 확인 불가"
        static let verifiedPrefix = "검증됨: "
        static let unverifiedPrefix = "미검증: "
        static let mainPresent = "메인 창 있음"
        static let mainMissing = "메인 창 없음 또는 AX 접근 불가"
        static let axUnavailable = "실행 중인 앱과 메인 창의 AX 접근 필요"
        static let axMatched = "현재 표시된 화면의 식별자 일치; 숨겨진 검색칸·채팅창은 미검사"
        static let axMissingPrefix = "누락: "
        static let listSeparator = ", "
        static let lockAvailable = "잠금 사용 가능"
        static let lockBusy = "다른 작업이 잠금 사용 중"
        static let lockUnavailable = "잠금 상태 확인 불가"
        static let windowCountPrefix = "메인 창 외 창 수: "
        static let windowCountUnknown = "AX 접근 불가: 창 수 확인 불가"
        static let frontmostTrue = "true (정보: 카카오톡이 맨 앞 앱)"
        static let frontmostFalse = "false (정보: 카카오톡이 맨 앞 앱이 아님)"
        static let bundleVersionKey = "CFBundleShortVersionString"
        static let memoryDatabase = ":memory:"
        static let cipherVersionQuery = "PRAGMA cipher_version"
    }
}
