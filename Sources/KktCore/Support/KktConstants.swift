import ApplicationServices
import Foundation

public enum KktConstants {
    public static let configPath = ("~/.config/kkt/config.json" as NSString).expandingTildeInPath
    public static let lockPath = ("~/.config/kkt/kkt.lock" as NSString).expandingTildeInPath
    public static let userIdEnv = "KKT_USER_ID"
    public static let compatModesNewestFirst = [4, 3]
    public static let commandName = "kkt"
    public static let version = "0.2.0"
    public static let serveBatchLimit = 500
    public static let serveDefaultInterval = 1.0
    public static let serveHeartbeatSeconds = 30.0
    public static let serveMaxConsecutiveErrors = 30
    public static let scrapWatchSeconds: TimeInterval = 120
    public static let scrapPendingMax = 200
    public static let serveCommandName = "serve"
    public static let serveSinceOption = "since-log-id"
    public static let serveIntervalOption = "interval"
    public static let databaseUnavailableCode = Code.databaseUnavailable
    public static let invalidIntervalCode = "invalid_interval"
    public static let successExitCode: Int32 = 0
    public static let failureExitCode: Int32 = 1

    public static let authCommandName = "auth"
    public static let commandDescription = "Local KakaoTalk tools for your own account."
    public static let authDescription = "Recover and verify the local account without server login."
    public static let okResult = "ok"
    public static let failedResult = "failed"
    public static let recoveryRange = 1...2_000_000_000
    public static let filePermissions = 0o600
    public static let directoryPermissions = 0o700
    static let zeroColumn: Int32 = 0
    static let zero = 0
    static let one = 1
    static let emptyText = ""
    static let newline = "\n"
    static let hexFormat = "%02x"
    static let hexRadix = 16
    static let hexByteWidth = 2
    static let encodeFailure = #"{"reason":"encode_failed","result":"failed"}"#

    enum Crypto {
        static let keyLength = 128
        static let iterations: UInt32 = 100_000
        static let databaseNameOffset = 28
        static let databaseNameLength = 78
        static let uuidPrefixLength = 5
        static let uuidDropLength = 7
        static let saltRatio = 0.3
        static let dot = "."
        static let first = "A"
        static let separator = "F"
        static let marker = "H"
        static let pipe = "|"
        static let hashHexLength = 128
        static let recoveryCheckInterval = 4096
        static let plistPrefix = "DENYFILEEXTIONSIONREVISION:"
        static let emptyAccountHash = "31bca02094eb78126a517b206a88c73cfa9ec6f704c7030d18212cace820f025f00bf0ea68dbf3f3a5436ca63b53bf7bf80ad8d5de7d8359d0b7fed9dbc3ab99"
    }

    enum Device {
        static let ioregPath = "/usr/sbin/ioreg"
        static let ioregArguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
        static let uuidPattern = #""IOPlatformUUID" = "([^"]+)""#
        static let uuidValuePattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        static let preferences = "Library/Preferences/com.kakao.KakaoTalkMac.plist"
        static let container = "Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Application Support/com.kakao.KakaoTalkMac"
        static let containerPreferences = "Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Preferences"
        static let plistPrefix = "com.kakao.KakaoTalkMac."
        static let plistName = "com.kakao.KakaoTalkMac.plist"
        static let plistExtension = ".plist"
        static let databasePattern = #"^[0-9a-f]{78}(\.db)?$"#
        static let uuidResource = "device_uuid"
        static let accountResource = "user_id"
    }

    enum Database {
        static let fileExtension = ".db"
        static let compatibilityPragma = "PRAGMA cipher_default_compatibility = "
        static let keyPragma = "PRAGMA KEY='"
        static let quote = "'"
        static let validationQuery = "SELECT count(*) FROM sqlite_master"
        static let resource = "database"
        static let nullTerminated: Int32 = -1
    }

    enum Code {
        static let busy = "busy"
        static let notFound = "not_found"
        static let ambiguous = "ambiguous_name"
        static let automation = "automation_failed"
        static let inputLocked = "input_locked"
        static let invalidLink = "invalid_link"
        static let invalidProfile = "invalid_profile"
        static let invalidNickname = "invalid_nickname"
        static let joinNotConfirmed = "join_not_confirmed"
        static let chatWindowOpen = "chat_window_open"
        static let kakaoNotRunning = "kakaotalk_not_running"
        static let kakaoInUse = "kakaotalk_in_use"
        static let readOnlySQL = "read_only_sql"
        static let databaseUnavailable = "database_unavailable"
        static let invalidConfig = "invalid_config"
    }

    static let messageEvent = "message"
    public static let scrapEvent = "scrap"
    static let scrapMessageType = 1
    static let scrapURLsKey = "urls"
    static let scrapDataKey = "universalScrapData"
    static let scrapAttachmentQuery = "SELECT attachment FROM NTChatMessage WHERE chatId=? AND logId=?"
    static let scrapAttachmentColumn: Int32 = 0
    static let heartbeatEvent = "heartbeat"
    static let errorEvent = "error"
    static let initialErrorCount = 0
    static let errorCountIncrement = 1
    static let serveEventsQuery = """
        SELECT m.logId, m.chatId,
               COALESCE(NULLIF(r.chatName, ''), NULLIF(meta3.groupNickname, ''), NULLIF(ol.linkName, ''),
                        NULLIF(du.friendNickName, ''), NULLIF(du.displayName, ''), NULLIF(du.nickName, '')),
               r.type, COALESCE(r.linkId, 0), m.authorId,
               COALESCE(NULLIF(a.friendNickName, ''), NULLIF(a.displayName, ''), NULLIF(a.nickName, ''),
                        NULLIF(fallback.friendNickName, ''), NULLIF(fallback.displayName, ''),
                        NULLIF(fallback.nickName, '')),
               m.type, m.message, m.attachment, m.sentAt
        FROM NTChatMessage m
        LEFT JOIN NTChatRoom r ON r.chatId = m.chatId
        LEFT JOIN NTChatMeta meta3 ON meta3.chatId = m.chatId AND meta3.type = 3
        LEFT JOIN NTOpenLink ol ON ol.linkId = r.linkId AND r.linkId != 0
        LEFT JOIN NTUser du ON du.userId = r.directChatMemberUserId AND du.linkId = 0
        LEFT JOIN NTUser a ON a.userId = m.authorId AND a.linkId = COALESCE(r.linkId, 0)
        LEFT JOIN NTUser fallback ON fallback.userId = m.authorId AND fallback.linkId = 0
        WHERE m.logId > ? AND m.logId < ? ORDER BY m.logId ASC LIMIT ?
        """
    static let pendingLogIdSentinel = Int64.max
    static let serveMaxLogIdQuery = "SELECT MAX(logId) FROM NTChatMessage WHERE logId < ?"
    static let noLogId: Int64 = 0

    enum ServeColumn {
        static let logId: Int32 = 0
        static let chatId: Int32 = 1
        static let chatName: Int32 = 2
        static let chatType: Int32 = 3
        static let linkId: Int32 = 4
        static let authorId: Int32 = 5
        static let authorName: Int32 = 6
        static let type: Int32 = 7
        static let text: Int32 = 8
        static let attachment: Int32 = 9
        static let sentAt: Int32 = 10
    }

    static let serveUserIdQuery = "SELECT userId FROM NTChatContext LIMIT 1"

    public static let automationCode = Code.automation
    static let mainWindowIdentifier = "Main Window"
    static let selfChatName = "self-chat (나와의 채팅)"
    static let singleUnit = 1
    static let uniqueMatchCount = 1
    static let normalizedSpace = " "
    static let unexpectedWindow = "unexpected_window"
    static let actionSettle = 0.3
    static let selectionSettle = 0.2
    static let windowPoll = 0.5
    static let openWindowTimeout = 8.0
    static let searchClearButtonTitle = "취소"
    static let searchButtonDescription = "검색"
    static let searchClearTimeout = 2.0
    static let searchClearPoll = 0.2
    static let searchFilterTimeout = 3.0
    static let chatListScrollSettle = 0.25
    static let restoreOpenPath = "/usr/bin/open"
    static let restoreBundleArgument = "-b"
    static let mainWindowBackgroundArgument = "-g"
    static let mainWindowPoll = 0.1
    static let mainWindowReopenTimeout = 5.0
    static let mainWindowActivationWait: TimeInterval = 2
    static let mainWindowMenuTimeout: TimeInterval = 2
    static let returnKeyCode: CGKeyCode = 36
    static let unicodeKeyCode: CGKeyCode = 0
    static let typeInterval = 0.03
    public static let associateMouseCursor: boolean_t = 1
    static let kakaoopenJoinFormat = "kakaoopen://join?l=%@"
    static let lockPollInterval = 0.2
    static let lockDirectoryPermissions = directoryPermissions
    static let lockFilePermissions: mode_t = 0o600
    static let invalidFileDescriptor: Int32 = -1
    static let systemCallSuccess: Int32 = 0
    static let zeroInterval: TimeInterval = 0
    static let minimumSendInterval = 2.0
    static let lastSendSuffix = ".last-send"

    public static let sendCommandName = "send"
    public static let sendChatIdOption = "chat-id"
    public static let sendTextOption = "text"
    public static let sendImageOption = "image"
    public static let sendDryRunOption = "dry-run"
    public static let sendViaCardRoomOption = "via-card-room"
    public static let sendViaCardUserOption = "via-card-user"
    public static let sendViaCardNicknameOption = "via-card-nickname"
    static let cardIdentityTextLimit = 20
    static let cardIdentityMinimumTextLength = 2
    // Message bubble bodies are AXTextArea in KakaoTalk 26.9; AXStaticText covers system lines (measured 2026-11-03).
    static let messageTextRoles: Set<String> = [kAXTextAreaRole as String, kAXStaticTextRole as String]
    static let textMessageType = 1
    static let recentTextsQuery = """
        SELECT message FROM NTChatMessage
        WHERE chatId=? AND type=? AND logId<? ORDER BY logId DESC LIMIT ?
        """
    public static let sentResult = "sent"
    public static let uncertainResult = "uncertain"
    public static let dryRunResult = "dry_run"
    public static let lockDefaultTimeout = 2.0
    static let sendVerifyTimeout = 10.0
    static let imageVerifyTimeout: TimeInterval = 30
    static let sendVerifyPoll = 0.5
    static let lockedInputMarker = "주의가 필요한 방"
    static let directRoomType = 0
    static let selfRoomType = 5
    static let noLinkId: Int64 = 0
    static let uniqueNameCount = 1
    static let countColumn: Int32 = 0
    static let noMatchingNames = 0
    static let pasteKey: CGKeyCode = 9
    static let imagePasteSettle = 2.0
    static let imageSendSettle = 2.0
    static let perImageSettle = 0.5
    static let clickCenterDivisor: CGFloat = 2
    static let imageSendSuffix = "개 전송"
    static let imageSheetTimeout: TimeInterval = 15
    static let imageSheetPoll: TimeInterval = 0.3
    static let backgroundPasteSettle: TimeInterval = 0.2
    static let backgroundSheetTimeout: TimeInterval = 2
    static let backgroundSheetPoll: TimeInterval = 0.1
    static let uploadCancelWarning = "채팅방을 닫으시겠습니까"
    static let uploadCancelButton = "취소"
    static let roomDisplayNameExpression =
        // KakaoTalk stores unset friend nicknames as '' (not NULL); without NULLIF a 1:1 room's name became ''
        // and every send to it failed as ambiguous_name (2026-11-03).
        "COALESCE(NULLIF(r.chatName,''), NULLIF(meta3.groupNickname,''), NULLIF(ol.linkName,''), "
            + "NULLIF(du.friendNickName,''), NULLIF(du.displayName,''), NULLIF(du.nickName,''))"
    static let roomJoins = """
        FROM NTChatRoom r
        LEFT JOIN NTOpenLink ol ON ol.linkId=r.linkId AND r.linkId!=0
        LEFT JOIN NTChatMeta meta3 ON meta3.chatId=r.chatId AND meta3.type=3
        LEFT JOIN NTUser du ON du.userId=r.directChatMemberUserId AND du.linkId=0
        """
    static let selfRoomDisplayNameExpression = """
        (SELECT COALESCE(NULLIF(nickName,''), NULLIF(displayName,'')) FROM NTUser
         WHERE userId = (\(serveUserIdQuery)) AND linkId = \(noLinkId))
        """
    static let roomQuery = "SELECT r.chatId, r.type, r.linkId, ol.linkUrl, "
        + "CASE WHEN r.type = \(selfRoomType) THEN " + selfRoomDisplayNameExpression
        + " ELSE " + roomDisplayNameExpression + " END " + roomJoins + " WHERE r.chatId=?"
    static let sameNameCountQuery = "SELECT COUNT(DISTINCT r.chatId) " + roomJoins
        + " WHERE " + roomDisplayNameExpression + " IN (?,?,?)"
    static let sentRowsQuery = """
        SELECT logId, authorId, message FROM NTChatMessage
        WHERE chatId=? AND logId>? AND logId<? ORDER BY logId
        """

    enum RoomColumn {
        static let chatId: Int32 = 0
        static let type: Int32 = 1
        static let linkId: Int32 = 2
        static let linkUrl: Int32 = 3
        static let displayName: Int32 = 4
    }

    enum SentColumn {
        static let logId: Int32 = 0
        static let authorId: Int32 = 1
        static let message: Int32 = 2
    }


    static let foregroundSettle = 0.3
    static let contactForegroundTimeout = 5.0
    static let scrollToBottomValue = 1.0
    static let scrollPageFraction = 0.9
    static let scrollFallbackStep = 0.03

    public static let joinCommandName = "join"
    public static let joinProfileOption = "profile"
    public static let joinNicknameOption = "nickname"
    public static let joinProfileKakao = "kakao"
    public static let joinProfileNickname = "nickname"
    public static let joinScreenTimeout = 8.0
    public static let joinDBTimeout = 15.0
    public static let joinButtonCover = "오픈채팅 참여하기"
    public static let joinButtonConfirm = "참여하기"
    public static let joinNicknamePlaceholder = "닉네임 입력"
    public static let joinKakaoProfileLabel = "카카오톡 프로필"
    public static let teamRequestButton = "참여 요청"
    public static let teamRequestedMarker = "참여 요청을 보냈습니다"
    public static let joinedResult = "joined"
    public static let alreadyMemberResult = "already_member"
    public static let requestedResult = "requested"
    public static let needsPasswordResult = "needs_password"
    public static let fullResult = "full"
    public static let endedResult = "ended"
    public static let ineligibleResult = "ineligible"

    public static let contactCommandName = "contact"
    public static let contactRoomOption = "room-chat-id"
    public static let contactUserOption = "user-id"
    public static let contactNicknameOption = "nickname"
    public static let cardButtonMaxDY: CGFloat = 120
    public static let cardScrollSteps = 8
    public static let cardLabelDirect = "1:1 채팅"
    public static let cardLabelAdd = "친구 추가"
    public static let cardLabelProfile = "프로필 보기"
    public static let forbiddenLabels: Set<String> = ["신고", "차단"]
    public static let openedResult = "opened"
    public static let alreadyContactResult = "already_contact"
    public static let cardNotVisibleCode = "card_not_visible"
    public static let buttonNotFoundCode = "button_not_found"
    public static let screenRecordingPermissionCode = "screen_recording_permission"
    public static let forbiddenLabelCode = "forbidden_label"
    public static let contactWindowMissingCode = "contact_window_not_found"
    public static let contactNotConfirmedCode = "contact_not_confirmed"
    public static let screenCaptureFailedCode = "screen_capture_failed"
    static let cardFoundPrefix = "card_found:"
    static let cardRowTolerance: CGFloat = 15
    static let cardCenterDivisor: CGFloat = 2
    static let cardPreviewMaxDY: CGFloat = 120
    static let contactAddAttempts = 2
    static let contactClickInterval = 0.05
    static let contactRecognitionLanguages = ["ko-KR", "en-US"]
    static let contactCandidateCount = 1
    static let contactDirectQuery = "SELECT chatId FROM NTChatRoom WHERE directChatMemberUserId=? AND type=0"
    static let contactFirstColumn: Int32 = 0
    static let joinCoverReason = "cover"
    static let joinProfileReason = "profile_choice"
    static let joinTeamReason = "team_request"
    static let joinOpenHost = "open.kakao.com"
    static let joinTeamHost = "invite.kakao.com"
    static let joinOpenPath = "o"
    static let joinTeamPath = "tc"
    static let joinHTTPS = "https"
    static let joinHTTP = "http"
    static let joinSchemeSeparator = "://"
    static let joinDefaultPrefix = "https://"
    static let joinPathSeparator: Character = "/"
    static let joinPathCount = 2
    static let joinPathKindIndex = 0
    static let joinPathCodeIndex = 1
    static let joinCodePattern = "^[A-Za-z0-9_-]+$"
    static let joinOpenScheme = "kakaoopen"
    static let joinTeamScheme = "kakaotalk"
    static let joinSchemeHost = "join"
    static let joinTeamSchemeHost = "teamchat"
    static let joinTeamSchemePath = "/join"
    static let joinCodeParameter = "l"
    static let joinTokenParameter = "token"
    static let joinFullMarkers = ["인원", "가득"]
    static let joinEndedMarkers = ["종료", "삭제"]
    static let joinIneligibleMarkers = ["참여할 수 없", "조건"]
    static let joinPasscodeMarkers = ["참여코드", "참여 코드", "비밀번호", "암호"]
    static let joinNicknameLabel = "닉네임"
    static let joinSnapshotDepth = 8
    static let joinInitialDepth = 0
    static let joinDepthIncrement = 1
    static let joinChatIdQuery = """
        SELECT r.chatId FROM NTChatRoom r JOIN NTOpenLink l ON l.linkId=r.linkId
        WHERE l.linkUrl LIKE '%/' || ?
        """
    static let joinKnownTitlesQuery = "SELECT " + roomDisplayNameExpression + " " + roomJoins
    static let joinFirstColumn: Int32 = 0
    static let frameMatchTolerance: CGFloat = 2
    static let windowLookupTimeout: TimeInterval = 2
    static let screencapturePath = "/usr/sbin/screencapture"
    static let screencaptureArguments = ["-x", "-o", "-l"]
    static let captureFileExtension = ".png"

    enum AX {
        static let windowMenu = "창"
        static let chatsMenuItem = "채팅"
        static let bundleId = "com.kakao.KakaoTalkMac"
        static let cell = "AXCell"
        static let button = "AXButton"
        static let checkBox = "AXCheckBox"
        static let scrollArea = "AXScrollArea"
        static let scrollBar = "AXScrollBar"
        static let verticalOrientation = "AXVerticalOrientation"
        static let table = "AXTable"
        static let row = "AXRow"
        static let image = "AXImage"
        static let staticText = "AXStaticText"
        static let textField = "AXTextField"
        static let chatrooms = "chatrooms"
        static let chatList = "_NS:63"
        static let chatNameLabels = ["_NS:40", "_NS:18"]
        static let selfBadge = "badge me"
        static let searchDepth = 10
        static let tabDepth = 3
    }
}
