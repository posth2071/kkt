# KktCore 라이브러리 사용법

`KktCore`는 macOS 카카오톡의 로컬 DB 읽기와 AX 자동화를 제공하는 Swift 라이브러리입니다. macOS 14 이상, Swift 6, Homebrew SQLCipher가 필요합니다. 권한·본인 계정 사용 조건은 [README](../README.md)를 따릅니다.

## SwiftPM에서 가져오기

```sh
brew install sqlcipher
```

사용할 패키지의 `Package.swift`에 의존성과 제품을 추가합니다. `OWNER`는 저장소 소유자 자리표시자이며, 비공개 저장소는 빌드 환경에 Git 읽기 인증이 필요합니다. 토큰을 매니페스트에 넣지 마세요. `v0.1.0` 태그가 게시된 뒤 사용하는 예시입니다.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyKakaoTool",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/OWNER/kkt.git", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyKakaoTool",
            dependencies: [.product(name: "KktCore", package: "kkt")]
        ),
    ]
)
```

`KktCore`의 공개 API는 `import KktCore`로 사용합니다. `@testable import`는 필요하지 않습니다. 아래는 호출 코드 예시이며, 실제 계정·DB·UI를 사용합니다. ID·링크·이름은 가상 값이고 `dryRun`도 창을 열 수 있습니다.

## 설정과 DB 연결

`KktConfig.load(path:environment:)`는 기본 `~/.config/kkt/config.json`을 읽고 `KKT_USER_ID`를 우선 적용합니다. `KktConfig.save(_:path:)`는 설정을 `0600`으로 저장합니다. `userId`가 없다면 먼저 CLI의 `kkt auth`를 실행하세요.

```swift
import Foundation
import KktCore

let config = try KktConfig.load(environment: ProcessInfo.processInfo.environment)
let database = try ReadQueries.retry {
    try KakaoDatabase.open(config: config)
}
defer { database.close() }
```

이후 예시는 위 `config`와 `database`를 같은 동기 실행 범위에서 사용한다고 가정합니다. 장시간 `ServeLoop.run`은 실행 범위를 점유하므로 다른 예시와 별도로 실행하세요.

- `KakaoDatabase.open(config:uuid:containerPath:)`: 기기 UUID와 설정의 사용자 ID로 키·파일명을 계산하고 로컬 DB를 읽기 전용으로 엽니다. SQLCipher 호환 모드는 기본 `[4, 3]` 순서입니다.
- `KakaoDatabase.open(databasePath:key:compatModes:)`: 별도로 준비한 DB를 엽니다. `key: nil`이면 암호화하지 않은 테스트 DB에도 사용할 수 있습니다.
- `DeviceInfo.platformUUID()`, `DeviceInfo.activeAccountHash()`: 로컬 기기 UUID·계정 해시를 조회합니다.
- `UserIdRecovery.recover(sha512Hex:range:workers:)`: 지정 범위에서 사용자 ID를 역산합니다. `auth`는 `KktConstants.recoveryRange`와 활성 CPU 수를 사용합니다.
- `KeyDerivation.secureKey(userId:uuid:)`, `KeyDerivation.databaseName(userId:uuid:)`: 키·DB 파일명 계산입니다. 키를 저장하거나 로그·출력으로 노출하지 마세요.

직접 SQL을 조회할 때는 `query(_:bind:row:)`, `SQLValue`, `Row`를 사용합니다. `Row`는 SQLite 문장에 연결된 일시적인 뷰이므로 콜백 안에서 값을 복사하고 콜백 밖으로 보관하지 마세요.

```swift
let roomID: Int64 = 18_000_000_000_000_001
let roomSQL = "SELECT chatId FROM NTChatRoom WHERE chatId = ?"
let firstColumn: Int32 = .zero
let ids: [Int64] = try database.query(roomSQL, bind: [.int64(roomID)]) {
    $0.int64(firstColumn)
}
```

DB 연결은 읽기 전용이며 준비된 문장이 쓰기 동작이면 `readOnlySQL`을 던집니다. 임의 SQL의 단일 문장·허용 구문 검증에는 아래 `ReadQueries.query`를 사용하세요.

## 읽기·검색

`ReadQueries(database:)`는 `chats(limit:)`, `messages(chatId:since:limit:)`, `search(text:chatId:since:limit:)`, `resolveChat(named:)`, `query(_:)`를 제공합니다. 반환 모델은 `ReadChat`, `ReadMessage`, `ChatNameResolution`, `ReadQueryResult`입니다.

```swift
let reads = ReadQueries(database: database)
let limit = KktConstants.Read.defaultLimit
let duration = "7d"
let keyword = "점심"
let displayName = "모집방"
let countSQL = "SELECT COUNT(*) FROM NTChatMessage"

let chats = try reads.chats(limit: limit)
let messages = try reads.messages(
    chatId: roomID, since: ReadQueries.parseSince(duration), limit: limit
)
let matches = try reads.search(text: keyword, chatId: roomID, limit: limit)
let resolution = try reads.resolveChat(named: displayName)
let count = try reads.query(countSQL)
print(KktOutput.line(chats))
print(KktOutput.line(count.rows))
```

`resolveChat`은 유일한 정확 일치를 우선하고, 아니면 부분 일치 후보가 하나여야 `chatId`를 반환합니다. 미확정 시 `candidates`를 확인하세요. `RoomNames`는 표시 이름·멤버 이름 대체를 처리합니다. `ReadOnlySQL.validate(_:)`는 읽기 SQL을 검증하고, `TableOutput`은 사람이 읽는 표를 만듭니다. `ReadQueries.retry`는 `KktError.busy`만 최대 3회 시도하고 소진 시 `databaseUnavailable`을 던집니다.

## 이벤트 스트림

`KakaoDatabase`는 `myUserId()`, `currentMaxLogId()`, `eventsAfter(logId:limit:myUserId:)`, `scrapAttachment(chatId:logId:)`를 제공합니다. `ServeLoop`는 조회·출력·시계·대기·중단 조건을 클로저로 받습니다.

```swift
let myUserID = try database.myUserId()
let runDuration: TimeInterval = 5
let stopAt = Date().addingTimeInterval(runDuration)
let loop = ServeLoop(
    fetch: { try database.eventsAfter(logId: $0, limit: $1, myUserId: myUserID) },
    fetchAttachment: { try database.scrapAttachment(chatId: $0, logId: $1) },
    maxLogId: { try database.currentMaxLogId() },
    emit: KktOutput.emitLine,
    sleep: { Thread.sleep(forTimeInterval: $0) },
    clock: { Date() },
    interval: KktConstants.serveDefaultInterval,
    shouldContinue: { Date() < stopAt }
)
let status = loop.run(since: nil)
```

`since: nil`이면 시작 시점의 최대 logId 이후부터 읽습니다. 저장한 커서를 주면 그 이후를 읽습니다. `run`은 동기·차단 방식이며 중단 조건을 확인해 종료코드를 반환합니다. `shouldContinue`는 기본값이 항상 `true`이므로 서비스 종료 조건을 직접 연결하세요. 이 조건은 반복 경계에서 검사하며 진행 중인 대기를 즉시 취소하지 않습니다.

`KktEvent`는 `Encodable`이며 `.message(...)`, `.heartbeat(maxLogId:)`, `.error(reason:)`, `.scrap(logId:chatId:attachment:)`로 만들 수 있습니다. `ServeCursor`는 메시지 이벤트를 기준으로 커서를 전진시킵니다. NDJSON 필드·재시도·미리보기 동작은 [출력 계약](reference.md#기계-출력-계약)을 따릅니다. ID는 `Int64`로 유지하세요.

## 글·사진 전송과 방 열기

`SendOperation(reader:interval:)`은 방 조회·중복 이름 확인·창 열기·입력 잠금 확인·전송·DB 확인·창 정리를 수행합니다. **UI 잠금은 호출자가 잡아야 합니다.** `execute`는 오류를 던지거나 `KktResult`를 반환합니다.

```swift
do {
    let lock = KktLock(path: config.lockPath)
    try lock.acquire(timeout: KktConstants.lockDefaultTimeout)
    defer { lock.release() }

    let operation = SendOperation(
        reader: database, interval: SendInterval(path: config.lockPath)
    )
    let text = "확인"
    let result = try operation.execute(
        chatId: roomID, text: text, images: [], dryRun: true
    )
    print(KktOutput.line(result))
}
```

`SendVerifier`는 본인 사용자 ID·시작 logId·정규화한 본문을 기준으로 전송을 확인합니다. 결과가 `uncertain`이면 이미 전송했을 수 있어 즉시 재시도하지 마세요. 저수준 `MessageInput`·`ImagePaste`를 직접 사용하면 전송 확인과 창 정리를 호출자가 책임져야 합니다.

사진을 보내면 `KktResult.imageRoute`가 `background` 또는 `foreground`입니다. `MessageInput.send`와 `ImagePaste.send`는 같은 값을 `ImageRoute?`로 반환합니다(사진이 없으면 `nil`). `background`는 비공개 API를 쓰는 `SkyLightFocus` 경로이고, 심볼이 없거나 시트가 뜨지 않으면 `foreground`로 전환합니다. 사용 가능 여부는 `SkyLightFocus.isAvailable()`로 확인합니다.

`ChatOpener`는 최소화되거나 닫힌 메인 창을 표시합니다. 작업 뒤 시작 전 상태로 되돌리려면 `MainWindowKeeper().preserving { ... }`로 감싸세요. CLI 명령은 이미 이렇게 합니다.

`execute(..., viaCard: CardRoute(roomChatId:userId:nickname:))`로 프로필 카드 폴백을 선택할 수 있습니다. 기본값은 `nil`이며 기존 검색 경로를 유지합니다. 직접방의 대상 해석 또는 창 열기에서 `ambiguous_name`·`not_found`가 발생한 경우에만 사용하며, `database.directChatId(userId:)`가 요청한 `chatId`와 같아야 합니다. `roomChatId`는 카드가 게시된 오픈채팅방, `nickname`은 카드에 표시된 이름입니다.

`execute(..., progress: { stage in ... })`로 진행 단계(`ProgressStage`)를 받을 수 있습니다. 기본값은 아무것도 하지 않으며, `stage.label`은 표시용 문구입니다. 콜백은 `execute`를 호출한 스레드에서 실행됩니다.

카드 경로는 `ContactFlow`·`ContactAXUI`의 OCR 탐색·클릭·포커스 복원을 공유하며, 카드 닉네임과 다른 저장 이름을 가진 새 1:1 창도 받을 수 있습니다. 전송 전 제목이 DB 방 이름과 같은지, 최근 type-1 메시지 20개 중 앞뒤 공백 제거 후 2자 이상인 본문이 메시지 표의 정적 텍스트 AX 값과 정확히 일치하는지 확인합니다. `KakaoDatabase.recentTexts(chatId:limit:)`는 최신순 원문을 반환하며, 빈 값·짧은 본문은 대상 확인에서 제외합니다. 텍스트 행이 전혀 없을 때만 제목 확인으로 진행하고, 대상 확인 실패 시 새 창을 닫은 뒤 `KktError.ambiguous`를 던집니다. 카드가 있던 오픈채팅 창은 정리하고, 1:1 창은 기존 전송·검증·창 정리 흐름에 넘깁니다. 카드 경로 오류 사유는 `ContactFlow.failureReason(_:)`로 보존할 수 있고, `KktResult` 필드는 동일합니다. `dryRun`에서도 카드 클릭과 필요한 친구 추가는 수행합니다.

`ChatOpener().open(_:)`은 `SendTarget.openLink(code:title:)`, `.direct(name:)`, `.group(name:)`, `.selfChat(name:)`를 받습니다. `RoomRow`에서 대상을 결정하는 `resolveTarget(chatId:room:sameNameCount:)`도 공개되어 있습니다. 직접 연 창은 반환된 핸들만 정리하세요.

```swift
do {
    let lock = KktLock(path: config.lockPath)
    try lock.acquire(timeout: KktConstants.lockDefaultTimeout)
    defer { lock.release() }

    let title = "모집방"
    let window = try ChatOpener().open(.group(name: title))
    defer { _ = AXHelpers.closeWindow(window) }
    if let openedTitle = AXHelpers.title(window) { print(openedTitle) }
}
```

`ChatOpener.prepareWindows()`는 실행 중인 앱·메인 창을 확인하고, 메인 창이 닫혀 있으면 다시 엽니다. `UserWindowGuard.check(windows:)`는 메인 창 외 창이 있으면 거절합니다. `KakaoApp.checkNotInUse()`는 카카오톡 전면 사용을 거절합니다. `ChatSearch`는 검색 텍스트·표시 상태, `FocusGuard`는 원래 앱 포커스 복원에 사용됩니다. 이들 저수준 API는 파일 잠금을 자동 획득하지 않습니다.

## 참여와 연락처

`JoinTarget.parse(_:)`와 `schemeURL(for:)`는 오픈채팅·팀채팅 링크를 해석합니다. `JoinFlow`는 `JoinUI`를, `ContactFlow`는 `ContactUI`를 받으므로 앱 연동이나 외부 경계 대체가 가능합니다. 실제 AX 구현은 `JoinAXUI`, `ContactAXUI`입니다.

```swift
do {
    try KakaoApp.checkNotInUse()
    let lock = KktLock(path: config.lockPath)
    try lock.acquire(timeout: KktConstants.lockDefaultTimeout)
    defer { lock.release() }

    let url = "https://open.kakao.com/o/AbCdEf12"
    let join = JoinFlow(
        ui: JoinAXUI(knownChatTitles: { try database.knownJoinChatTitles() }),
        lookupChatId: { try database.joinedChatId(code: $0) }
    )
    let joinResult = join.run(url: url, profile: .kakao, dryRun: true)
    print(KktOutput.line(joinResult))
}
```

```swift
do {
    try KakaoApp.checkNotInUse()
    let lock = KktLock(path: config.lockPath)
    try lock.acquire(timeout: KktConstants.lockDefaultTimeout)
    defer { lock.release() }

    let userID: Int64 = 12345
    let nickname = "상대닉네임"
    let ui = ContactAXUI(room: {
        guard let room = try database.room(chatId: roomID) else {
            throw KktError.notFound(String(roomID))
        }
        return room
    }, recognizeWindow: { try ScreenText.recognize(window: $0) })
    let contact = ContactFlow(ui: ui, lookupChatId: { try database.directChatId(userId: $0) })
    let contactResult = contact.run(userId: userID, nickname: nickname, dryRun: true)
    print(KktOutput.line(contactResult))
}
```

`ContactAXUI`는 프로필 카드가 있는 오픈채팅방을 대상으로 합니다. `ScreenText`·`TextBox`·`locateCardButtons`는 화면 OCR과 카드 버튼 위치 판정에 사용됩니다. 두 Flow는 실패를 `KktResult(result: "failed", reason: ...)`로 반환하므로 `throws` 처리만으로 성공을 판단하지 마세요.

## 공지 읽기

`NoticeReader(fetch:screen:)`는 DB 우선·긴 미리보기와 삭제 표시 공지, 공지 행이 없는 방의 화면 보완·잘린 결과 반환 정책입니다. `NoticeResult`는 `chatId`, `text`, `source`, `truncated`, `updatedAt`, `messageDeleted`를 제공합니다. `messageDeleted`는 `databaseNotice`가 읽은 행의 삭제 표시이며 JSON 출력에는 포함되지 않습니다. 화면 접근 잠금은 `screen` 클로저에서만 잡을 수 있습니다.

```swift
let noticeReader = NoticeReader(fetch: { id in
    try ReadQueries.retry {
        try NoticeReader.databaseNotice(database: database, chatId: id)
    }
}, screen: { id in
    let lock = KktLock(path: config.lockPath)
    try lock.acquire(timeout: KktConstants.lockDefaultTimeout)
    defer { lock.release() }
    let target = try NoticeReader.screenTarget(database: database, chatId: id)
    return try NoticeAX().read(target)
})
let notice = try noticeReader.read(chatId: roomID)
print(KktOutput.line(notice))
```

`NoticeAX`는 공지 배너에서 상세 화면의 본문을 읽습니다. 화면 접근이 실패해도 DB 공지가 있으면 `source: "truncated"`, `truncated: true`가 될 수 있으므로 해당 필드를 확인하세요. DB 공지가 없으면 `screen` 클로저의 오류를 그대로 던지고, 배너가 없어 `nil`이면 `KktError.notFound`를 던집니다.

## 진단과 오류

```swift
let report = DoctorChecks(config: config, probes: .live(config: config))
    .run(executablePath: CommandLine.arguments[.zero])
print(report.humanOutput)
print(KktOutput.line(report))
let diagnosticExitCode = report.exitCode
```

`DoctorChecks.Probes`의 공개 이니셜라이저에 파일 접근·권한·SQLCipher·DB 키·프로세스·버전·AX 스냅샷·잠금·전면 여부 클로저를 전달할 수도 있습니다. `DoctorCheck`는 `id`, `status`(`ok`/`warn`/`fail`), `detail`, 선택 `fix`를 갖습니다. `DoctorReport.exitCode`는 `fail`이 있으면 `1`입니다. `AXIdentifierTable.Snapshot`과 `AXIdentifierTable.missing(in:)`은 관찰한 AX 요소와 기준표를 비교합니다. 현재 보이지 않는 화면까지 검사하지는 않습니다.

`KktError.code`는 [reason 코드](reference.md#reason-코드)에 대응합니다. 연관 값이 있는 `.automation(String)`의 `.code`는 일반 `automation_failed`입니다. `contact`의 세부 오류 코드를 보존하려면 `ContactFlow.failureReason(_:)`를 사용합니다. `KktOutput.line(_:)`은 JSON 문자열, `emit(_:)`과 `emitLine(_:)`은 표준출력을 제공합니다.

## 스레드와 잠금

- `KakaoDatabase`는 `SQLITE_OPEN_NOMUTEX`로 열고 `Sendable`을 제공하지 않습니다. 연결 하나를 여러 스레드·Task에서 동시에 사용하거나 `Row`를 탈출시키지 마세요. 호출자가 연결별 접근을 직렬화하고 필요하면 별도 연결을 사용합니다.
- UI 흐름은 동기식이며 AppKit·AX·클립보드·키 이벤트와 `Thread.sleep`을 사용합니다. 호출 자체가 스레드 안전성을 보장하지 않습니다. AppKit 연동은 호스트 앱의 메인 스레드 정책을 지키고, 같은 UI에 대한 작업은 한 실행 경로에서 순차 처리하세요. 차단 호출을 메인 스레드에서 오래 실행하면 호스트 UI가 멈출 수 있습니다.
- `KktLock`은 `flock` 기반 프로세스 간 배타 잠금입니다. 모든 UI 호출자가 **같은 `lockPath`**를 사용하고, 창 열기부터 전송 확인·창 정리까지 보유해야 합니다. 별도 경로는 서로 보호하지 못합니다. 스레드 간 DB 안전성을 대신하지도 않습니다.
- `acquire(timeout:)`는 제한 시간 후 `busy`를 던집니다. `release()`를 `defer`로 호출하세요. 같은 인스턴스의 재획득은 참조 횟수를 세는 중첩 잠금이 아니므로 계층마다 획득·해제하지 마세요.
- `SendInterval`은 `<lockPath>.last-send`로 최소 2초 간격을 공유합니다. `waitIfNeeded()` → 전송 → `record()`를 잠금 안에서 실행해야 합니다. `SendOperation`은 이 순서를 수행하지만 잠금은 획득하지 않습니다.
- `ServeLoop`는 UI를 사용하지 않아 UI 잠금이 필요 없습니다. `emit`·`fetch`·시계·중단 조건은 동기 호출되며, 외부 스레드에서 중단 상태를 바꾸면 그 상태의 동기화도 호출자 책임입니다.

## 모듈 구성

| 디렉터리 | 주요 공개 진입점·역할 |
|---|---|
| `Database` | `KakaoDatabase`, `SQLValue`, `Row`, `DeviceInfo`, `KeyDerivation`, `UserIdRecovery`: DB 연결·계정 정보·키 계산 |
| `Serve` | `ServeLoop`, `ServeCursor`, `KktEvent`, DB 이벤트 조회 확장 |
| `UI` | `ChatOpener`, `ChatSearch`, `KakaoApp`, `AXHelpers`, `BackgroundInput`, `FocusGuard`, `UserWindowGuard`; 내부 메인 창 복구 |
| `Send` | `SendOperation`, `SendTarget`, `CardRoute`, `RoomRow`, `MessageInput`, `ImagePaste`, `SendVerifier` |
| `Join` | `JoinTarget`, `JoinProfile`, `JoinFlow`, `JoinUI`, `JoinAXUI`, `JoinScreenReader` |
| `Contact` | `ContactFlow`, `ContactUI`, `ContactAXUI`, `ScreenText`, `TextBox`, 카드 위치 판정 함수 |
| `Read` | `ReadQueries`, `ReadChat`, `ReadMessage`, `ReadQueryResult`, `RoomNames`, `ReadOnlySQL`, `TableOutput` |
| `Notice` | `NoticeReader`, `NoticeResult`, `NoticeAX` |
| `Doctor` | `DoctorChecks`, `DoctorCheck`, `DoctorReport`, `AXIdentifierTable` |
| `Support` | `KktConfig`, `KktConstants`, `KktError`, `KktResult`, `KktOutput`, `KktLock`, `SendInterval` |

구현은 `Sources/KktCore/`에 있고, 인자 파싱·종료코드·CLI 잠금 연결은 `Sources/kkt/`에 있습니다. 라이브러리에서 CLI 전용 내부 타입을 사용하지 마세요.
