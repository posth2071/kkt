> 이 문서는 최초 설계·구현 계획의 원본 기록이며, 현재 사용법은 [README](../../../README.md)를 기준으로 합니다.

# kkt — 사용자 전용 카카오톡 맥 CLI 설계서

- 작성: 2026-11-03 (승인 전 초안)
- 저장소: `<repo>` (독립 레포, GitHub **<owner> 비공개**)
- 실행 파일: `kkt`

## 1. 왜 만드나

카톡 모집 감시(watcher)와 미션·리뷰 자동화는 맥 카카오톡을 읽고(암호화 DB) 조작(AX 자동화)해야 한다. 지금은 남의 오픈소스
`kakaocli`(silver-flight-group, Swift, MIT)를 복제한 포크(`~/.local/src/kakaocli`, 브랜치 `local/kakaotalk-26.9`) 안에 `kkt` 를
덧붙여 쓰고, 읽기는 셸 래퍼 `~/.local/bin/kakao` + `kakao-names`(Python)로 한다. 사용자가 원한 것은 **두 오픈소스 CLI
(`kakaocli`, `openkakao-cli`(Rust, MIT))와 카카오톡 앱 자체를 rea MCP(Ghidra)로 분석해, 이 맥·이 사용 방식에 맞춘 CLI 를
새로 만들어 깃에 올리는 것**이다. 남의 포크를 계속 고쳐 쓰는 것이 아니다.

## 2. 목표 / 비목표 / 반목표

**목표**
- 하나의 Swift 실행 파일 `kkt` 가 watcher 와 사람(터미널·스킬)이 쓰는 카톡 기능을 모두 제공한다.
- watcher 는 실행 파일 경로(`kktPath`)만 바꾸면 그대로 동작한다(출력 계약 유지, 5절).
- 카톡 업데이트로 AX 구조가 바뀌면 `kkt doctor` 로 바로 어디가 깨졌는지 안다.
- 사용자가 카톡을 쓰는 중에도 방해하지 않는다(포커스·창·검색어 보존).

**비목표**
- 카카오 서버 로그인·서버 API 사용(계정 차단 위험). LOCO 프로토콜 구현.
- 다른 사람의 맥·다른 카톡 계정 범용 지원(사용자 ID·기기 1대 기준. 단, 하드코딩하지 않고 설정·역산으로 얻는다).
- 윈도우·iOS.

**반목표 (동작해도 이러면 실패)**
- 사용자가 쓰던 채팅 창을 닫거나, 그 창 입력칸에 글자가 들어간다.
- 사용자의 채팅 목록 검색어를 지우고 되돌리지 않는다.
- 사용자 모르게 카톡을 앞으로 가져온 채 둔다(잠깐 앞으로 오는 경우는 7절의 허용 목록만).
- 비밀(DB 키, 토큰)을 파일·로그·출력에 남긴다.

## 3. 사용자가 정한 것

| 항목 | 결정 |
|---|---|
| 위치·계정 | 워크스페이스 밖 `<repo>`, GitHub <owner> 비공개 |
| v1 범위 | watcher 핵심(serve·send·join·contact·키 계산) + 읽기·검색 + 사진 전송 + doctor + 방 공지 전문 읽기 |
| 포크본 | 새 CLI 가 완성될 때까지 그대로 운영, 새 동작(창 기다리기 등)은 새 CLI 에만 |
| 열린 채팅 창 | 사용자가 연 채팅 창이 있으면 닫지 않는다. kkt 는 바로 `chat_window_open` 으로 거절, watcher 가 재시도하다 2분이 지나면 텔레그램에 "카톡 채팅 창을 닫아 주세요"를 한 번 알리고 창이 닫힐 때까지 계속 대기 (11절 1·3) |
| 사진 위치 등 watcher UX | 기존 결정 유지(카드 아래 큰 사진 등) |

## 4. 출처와 분석 방법

- **우리 코드(그대로 옮김)**: 포크에서 우리가 쓴 kkt 전부 — `ServeLoop`(scrap 이벤트 포함), `ChatOpener`, `ChatSearch`,
  `MainWindowReopener`, `chatListRows`(AXVisibleRows), `BackgroundInput`, `FocusGuard`, `JoinFlow`/`JoinAXUI`/`JoinTarget`,
  `ContactFlow`/`CardLocator`/`ScreenText`(Vision OCR), `SendVerifier`, `KktLock`, `KktOutput`, 테스트.
- **kakaocli(MIT) 에서 필요한 부분만 이식**: SQLCipher 열기, `KeyDerivation`(PBKDF2-SHA256 10만 회, 기기 UUID + 사용자 ID),
  `DeviceInfo`, AX 헬퍼 중 쓰는 것. `LICENSE` 의 원저작권 고지를 `THIRD_PARTY_NOTICES.md` 에 남긴다. 안 쓰는 것
  (harvest, LoginAutomator, CredentialStore, Webhook) 은 가져오지 않는다.
- **openkakao-cli(Rust, MIT) 에서 배울 안전장치**: 중복 이름 거부, 전송 후 재확인, 전송 간격 제한(rate limit). 코드를 옮기기보다
  동작을 Swift 로 다시 구현하고, 참고한 부분은 같은 고지 파일에 적는다.
- **카카오톡 앱(rea MCP + Ghidra 프로젝트 `~/.local/share/kakao-re/ghidra-26.9.0`)**: 오픈소스에 없는 사실을 확인하는 데 쓴다.
  - 사용자 ID 역산: plist 키 `DENYFILEEXTIONSIONREVISION:<sha512(userId)>` (현재 래퍼가 하는 일) 의 생성 위치·형식.
  - 방 공지 전문이 있는 곳(DB `NTChatMeta` type 1 `content`? 별도 캐시? 서버 요청뿐?) — 6.5 참고.
  - 카톡 버전별 AX 식별자(`Main Window`, `chatrooms`, `_NS:40`/`_NS:18`, 입력칸, 검색칸) — doctor 의 기준표.
  - URL 스킴(`kakaoopen://join`, `kakaotalk://teamchat/join`) 동작.

## 5. 지켜야 할 계약 (watcher 호환)

watcher(`review-agent-kakao`)가 이미 의존한다. 이름·인자·출력 모양을 바꾸지 않는다.
- `kkt serve [--since-log-id N] [--interval S]` → 표준출력 NDJSON. 이벤트 `message`(logId, chatId, chatName, chatType, linkId,
  authorId, authorName, isFromMe, type, text, attachment, sentAt), `heartbeat`(maxLogId), `error`(reason), `scrap`(logId, chatId,
  attachment). 16자리 넘는 id 는 숫자 그대로(받는 쪽이 문자열로 다룸). 미전송 로컬 메시지(logId=Int64.max)는 커서를 움직이지 않는다.
- `kkt send --chat-id <id> [--text t] [--image p ...] [--dry-run]`, `kkt join <url> [--profile kakao|<이름>] [--nickname n] [--dry-run]`,
  `kkt contact --room-chat-id <id> --user-id <id> --nickname <n> [--dry-run]` → 한 줄 JSON `{"result": "sent|dry_run|failed|uncertain|joined|requested|already_member|...", "reason": "<snake_case>", ...}`.
  기존 reason 코드(`busy`, `not_found`, `ambiguous_name`, `automation_failed`, `input_locked`, `invalid_link`, `invalid_profile`,
  `invalid_nickname`, `join_not_confirmed`, `database_unavailable`, `invalid_interval` 등)는 유지하고 **`chat_window_open` 을 추가**한다.
- 잠금 파일 하나로 UI 조작을 직렬화한다(동시에 두 개 금지). serve 는 잠금을 잡지 않는다.

## 6. v1 명령

| 명령 | 하는 일 |
|---|---|
| `serve` | 위 계약 그대로. DB 는 한 번 열어 두고 1초 간격 폴링. 링크 글은 120초 동안 미리보기 갱신을 다시 확인해 `scrap` 이벤트 |
| `send` | 방 열기 → 입력 잠김 확인 → 글 전송(백그라운드) / 사진 전송(카톡을 잠깐 앞으로 — 7절) → DB 로 전송 확인. 전송 간격 최소 2초 |
| `join` | 오픈채팅 링크 참여(프로필 선택·닉네임 포함), 팀채팅 참여 요청 |
| `contact` | 프로필 카드 판매자 1:1 열기(친구 추가 포함, OCR) |
| `chats` | 방 목록: chatId, 표시 이름(DB 로 계산 — 방 제목 → 오픈채팅 이름 → 1:1 상대 → 단체방 별명 → "A, B 외 n명"), 종류, 마지막 시각, 안 읽은 수 |
| `messages` | `--chat-id` 또는 `--chat "이름"`(여러 개면 후보 출력 후 실패), `--since 7d`, `--limit` |
| `search` | 본문 검색(방·기간 필터). DB 를 직접 LIKE 로 찾는다(빠른 전문 검색은 watcher 색인 `kk` 의 몫) |
| `query` | 읽기 전용 SQL(SELECT/WITH/PRAGMA 만 허용) |
| `notice` | 방 공지 전문(6.5) |
| `doctor` | 6.6 |
| `auth` | 사용자 ID 역산·확인(키는 출력하지 않음), 설정 파일에 사용자 ID 저장 |

출력: 기계용 명령(serve/send/join/contact)은 JSON 고정. 사람용 명령(chats/messages/search/notice/doctor)은 기본 표 형태,
`--json` 이면 JSON.

### 6.5 방 공지 전문
지금 DB 의 공지 메시지(type 24) attachment 는 약 450자에서 잘린다. 순서: (1) rea 로 전문이 DB 어딘가(예: `NTChatMeta`)에 있는지
확인해 있으면 DB 에서 읽는다. (2) 없으면 방의 공지 화면을 백그라운드로 열어 AX 로 읽는다(포커스 유지, 창은 kkt 가 연 것만 닫음).
(3) 둘 다 안 되면 잘린 본문 + `truncated: true` 를 돌려준다. 어느 경로인지 출력에 `source` 로 표시.

### 6.6 doctor
항목별 ok/warn/fail + 고치는 방법 한 줄:
전체 디스크 접근(DB 열림), 손쉬운 사용(AXIsProcessTrusted), 화면 기록(CGPreflightScreenCaptureAccess), sqlcipher 설치,
사용자 ID·DB 키 검증, 카톡 실행 여부·버전(검증된 버전 목록과 비교), 메인 창 존재, AX 식별자(채팅 탭·채팅 목록 표·이름 라벨·
검색칸·입력칸) 해석, 잠금 파일 상태, 열린 채팅 창 수. launchd 에서 돌 때(watcher)와 터미널에서 돌 때 권한 주체(node vs 터미널)가
다르다는 점을 출력에 적는다.

## 7. 화면·포커스 규칙

- 기본은 백그라운드: AX 선택 + 카톡 pid 로만 보내는 키 이벤트, `open -g`.
- 카톡이 잠깐 앞으로 오는 것은 다음만 허용하고, 끝나면 즉시 원래 앱으로 되돌린다: 사진 붙여넣기, 프로필 카드 버튼 클릭,
  `kakaoopen://` 링크 열기, 닫힌 메인 창 다시 띄우기(카톡이 스스로 1~1.5초 활성화, 2026-11-03 실측), 공지 배너 클릭.
- 사용자가 연 채팅 창이 있으면 UI 조작을 시작하지 않고 `chat_window_open`(3절). kkt 가 연 창은 kkt 가 닫는다.
- 채팅 목록 검색어는 바꿨으면 반드시 되돌린다.
- 채팅 목록 행은 `AXVisibleRows` 로만 읽는다(AXChildren 은 1,385행이라 한 번에 6~9초, 2026-11-03 실측).

## 8. 설정·비밀

- 설정 `~/.config/kkt/config.json`(0600): 사용자 ID, 검증된 카톡 버전. DB 키는 매 실행 계산하고 저장하지 않는다.
- 잠금 `~/.config/kkt/kkt.lock`. 로그는 기본 없음(오류는 reason 코드로만).

## 9. 테스트·완료 기준

- XCTest. AX·DB·시계·프로세스 실행은 주입해 단위테스트. 포크의 kkt 테스트(116개)를 옮겨 통과시킨다.
- 실측 체크리스트(사용자 확인): serve 백필·실시간, scrap, send(나와의 채팅), dry-run 모집방(`input_locked`, 10초 이내),
  창 닫힘 상태, 열린 채팅 창 거절, 검색어 복원, join/contact dry-run, 사진 전송(나와의 채팅), notice, doctor.
- watcher 를 새 `kkt` 로 바꾼 뒤 하루 운영해 이상 없으면 포크본·`kakao` 래퍼·`kakaocli-patched` 를 정리(삭제는 사용자 확인 후).

## 10. 릴리스·저장소 규칙

- 트렁크(main) + 태그 `vX.Y.Z`, Conventional Commits, <owner> 계정 확인 후 푸시.
- README: 설치(brew sqlcipher, `swift build -c release`, `~/.local/bin/kkt`), 권한 3종, 명령, 약관·면책 고지(비공식·자기 계정 전용).
- 구현은 Codex 위임, 계획·실측·검증은 Fable(워크스페이스 공통 규칙과 같게).

## 11. 정리된 세부 결정 (설계 검토 후, Fable 판단 — 사용자 확인 대상)

1. **watcher 수정도 이번 작업에 포함한다.** 지금 watcher 는 `failed`+reason 을 받으면 카드를 바로 실패로 확정하고 재시도가 없다.
   `chat_window_open` 은 실패가 아니라 대기로 다룬다: 카드는 대기열에 남기고 10초마다 재시도, 2분이 지나면 텔레그램에 한 번 알림,
   창이 닫히면 이어서 진행, 그 사이 카드가 마감되면 중단. 그래서 "watcher 는 경로만 바꾸면 된다"(5절)는 이 한 가지를 빼고의 이야기다.
2. **전환 기간**: 새 실행 파일은 `~/.local/bin/kkt-next` 에 설치해 실측하고, 전환할 때 `~/.local/bin/kkt` 를 바꿔치기한다(watcher
   `kktPath` 그대로). 전환 전까지 새 kkt 는 포크와 **같은 잠금 파일** `~/.review-automation/kakao/kkt.lock` 을 쓴다(설정으로 경로 지정,
   기본값은 8절). 동시에 UI 를 조작할 일이 없다.
3. **"사용자 창" 판정**: 메인 창이 아닌 카톡 창은 종류와 상관없이 모두 사용자 창으로 보고 거절한다(닫지 않는다). kkt 가 연 창은
   같은 실행 안에서 반드시 닫는다(defer). kkt 가 비정상 종료로 창을 남기면 사용자에게 닫아 달라는 알림이 가는데, 드문 경우라 받아들인다.
   doctor 의 "열린 채팅 창 수" 는 메인 창이 아닌 창의 수다.
4. **전송 간격**: 마지막 전송 시각을 잠금 파일 옆에 기록하고, 2초가 안 됐으면 잠금을 잡은 채 기다린다(새 reason 없음).
5. **rea 분석은 계획의 첫 단계**로 넣고 시간 상한을 둔다(한 단계, 약 2시간). 공지 전문이 서버에서만 온다고 확인되면 곧바로 AX 경로로
   확정한다. 사용자 ID 역산은 지금 래퍼의 방식(검증됨)을 기본으로 이식하고, 분석은 확인용이다.

## 12. 빌더에게 맡기는 것

- 패키지·타깃·파일 구성, 내부 타입 이름(5절 계약만 지키면 됨).
- 사람용 출력의 표 모양.
- 포크 코드 이식 순서.
