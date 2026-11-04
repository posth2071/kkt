# kkt 레퍼런스

명령, 설정, 기계 출력 계약의 세부 사양입니다. 처음 쓰신다면 [README](../README.md)부터 보세요.

## 설치와 빌드 세부

스크립트는 기본 릴리스 빌드가 실패하면 `--build-system native`, 이어서 `--build-system native --disable-sandbox`로 재시도합니다. 기본 설치 대상이 심볼릭 링크이면 설치를 거절하며, 명시적인 경로 인자는 계속 지원합니다. 설치 경로와 진단 명령을 출력하고 `doctor`를 자동 실행하지는 않습니다. `~/.local/bin`을 `PATH`에 추가하거나 전체 경로로 실행하세요.

수동 빌드와 테스트:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/kkt-clang-module-cache swift build -c release --build-system native --disable-sandbox
CLANG_MODULE_CACHE_PATH=/tmp/kkt-clang-module-cache swift test --build-system native --disable-sandbox
```

수동 빌드 결과는 `.build/release/kkt`입니다. SwiftPM 의존성으로 사용하는 방법은 [라이브러리 가이드](library.md)에 있습니다.

## 첫 실행 세부

`auth`는 설정에 사용자 ID가 없으면 로컬 plist의 계정 해시에서 ID를 역산하고, DB 열기를 검증한 뒤 `~/.config/kkt/config.json`에 저장합니다. 첫 역산에는 시간이 걸릴 수 있습니다. DB 키는 매 실행 계산하며 설정·로그·출력에 저장하지 않습니다. 설정 파일 권한은 `0600`입니다.

`doctor`는 실행 파일 경로와 권한 주체 안내, 권한 3종, SQLCipher, 사용자 ID·DB 키, 카카오톡 실행·버전, 메인 창·현재 보이는 AX 식별자, 잠금, 사용자 창 수, 전면 앱 여부와 사진 백그라운드 경로 사용 가능 여부를 진단합니다. 각 항목은 `ok`/`warn`/`fail`이며, `fail`이 있으면 종료코드 `1`입니다. 숨겨진 화면까지 검증하지 않으므로 `ok`만으로 모든 UI 동작의 호환성을 보장하지는 않습니다.

## 설정

| 항목 | 기본값·동작 |
|---|---|
| `userId` | 선택적 양의 정수. `auth`로 복구·저장 |
| `lockPath` | `~/.config/kkt/kkt.lock`. UI 작업끼리 같은 경로 사용, `~` 확장 지원 |
| `verifiedKakaoVersions` | 기본 `[]`. 실제 검증한 카카오톡 버전 문자열 목록; 목록에 없으면 `doctor`에서 `warn` |
| 환경변수 `KKT_USER_ID` | 설정 파일의 `userId`보다 우선. 양의 정수만 허용 |

`config.json` 예시입니다. `userId`는 `auth`가 저장한 값을 유지하세요. 버전은 앱의 `CFBundleShortVersionString`과 **정확히 일치**해야 합니다(26.9 검증 기록의 앱 버전은 `26.9.0`).

```json
{
  "lockPath": "~/.config/kkt/kkt.lock",
  "verifiedKakaoVersions": ["26.9.0"]
}
```

UI 작업은 파일 잠금으로 직렬화합니다. 마지막 전송 시각은 `<lockPath>.last-send`에 기록하고, 최소 전송 간격 2초가 지나지 않았으면 잠금을 보유한 채 기다립니다. `serve`와 DB 읽기 전용 명령은 UI 잠금을 잡지 않습니다. `notice`는 화면 경로를 사용할 때만 잡습니다.

## 명령

ID·이름·링크는 가상 예시입니다. 본인 계정의 값으로 바꿔 사용하세요. **`--dry-run`도 방이나 참여 링크를 열어 화면을 확인할 수 있습니다.**

| 명령 | 용도·주요 옵션 | 예시 |
|---|---|---|
| `serve` | DB 이벤트 스트림. `--since-log-id`, `--interval`(기본 1초) | `kkt serve --since-log-id 18000000000000001 --interval 1` |
| `send` | 글·사진 전송. `--chat-id`, `--text`, `--image`, `--dry-run`, `--via-card-room`, `--via-card-user`, `--via-card-nickname` | `kkt send --chat-id 18000000000000001 --text "확인" --image "$HOME/Pictures/photo.png" --dry-run` |
| `join` | 오픈채팅 참여·팀채팅 참여 요청. `--profile`, `--nickname`, `--dry-run` | `kkt join "https://open.kakao.com/o/AbCdEf12" --profile nickname --nickname "내닉네임" --dry-run` |
| `contact` | 방의 프로필 카드에서 친구 추가·1:1 채팅 열기 | `kkt contact --room-chat-id 18000000000000001 --user-id 12345 --nickname "상대닉네임" --dry-run` |
| `chats` | 방 목록. `--limit`(기본 50), `--json` | `kkt chats --limit 5 --json` |
| `messages` | 방의 메시지. `--chat-id` 또는 `--chat`, `--since`, `--limit`(기본 50) | `kkt messages --chat "모집방" --since 7d --limit 50 --json` |
| `search` | 본문 SQL LIKE 검색. `--chat-id`, `--since`, `--limit`(기본 20) | `kkt search "점심" --since 12h --limit 20 --json` |
| `query` | 읽기 전용 SQL | `kkt query "SELECT COUNT(*) FROM NTChatMessage" --json` |
| `notice` | 방 공지 읽기. `--chat-id` 또는 `--chat` | `kkt notice --chat "미션방" --json` |
| `doctor` | 환경·호환성 진단 | `kkt doctor --json` |
| `auth` | 로컬 사용자 ID 복구·DB 검증·설정 저장 | `kkt auth` |

- `--since`는 `7d`, `12h`, `30m` 같은 기간이며 `s`/`m`/`h`/`d`/`w` 단위를 지원합니다.
- `--chat`은 DB 표시 이름을 사용합니다. 유일한 정확 일치를 우선하고, 그렇지 않으면 부분 일치 후보가 하나여야 합니다. 후보가 없거나 여러 개면 후보 목록과 종료코드 `2`를 반환합니다. `--chat-id`로 명확히 지정할 수 있습니다.
- `send --image` 뒤에는 여러 이미지 경로를 전달할 수 있습니다. `join --profile`은 `kakao`(기본) 또는 `nickname`이며, 후자는 `--nickname`이 필요합니다. 팀채팅 링크는 `https://invite.kakao.com/tc/<token>` 형식을 지원합니다.
- `send`의 선택 옵션 `--via-card-room <Int64>`(프로필 카드가 게시된 오픈채팅방 ID), `--via-card-user <Int64>`(상대 사용자 ID), `--via-card-nickname <String>`(카드의 닉네임)을 모두 지정하면, 1:1 방의 이름 검색이 `ambiguous_name` 또는 `not_found`로 실패했을 때 카드로 방을 엽니다. 일부만 지정하면 기존 검색 경로를 유지합니다. 사용자 ID가 대상 1:1 방의 구성원과 다르면 거절합니다.
- 카드 경로는 `contact`와 같은 OCR·스크롤·친구 추가 흐름을 사용하며, 클릭 중 잠시 카카오톡을 활성화한 뒤 포커스를 복원합니다. 새 창의 제목이 DB 방 이름과 같고, 최근 텍스트 메시지 20개 중 앞뒤 공백 제거 후 2자 이상인 본문 하나가 메시지 표의 AX 값과 일치해야 전송합니다. 텍스트 행이 전혀 없을 때만 제목으로 확인하며, 확인 실패 시 창을 닫고 `ambiguous_name`을 반환합니다. `--dry-run`도 카드 클릭·필요한 친구 추가·대상 확인은 수행하지만 메시지는 전송하지 않습니다. 카드 경로 오류는 `card_not_visible`, `button_not_found`, `contact_window_not_found` 등 기존 사유를 반환하며 JSON 필드는 바뀌지 않습니다.
- `query`는 `SELECT`/`WITH`/`PRAGMA`로 시작하는 단일 문장만 허용합니다. 쓰기·`ATTACH`·여러 문장은 `read_only_sql`로 거절하고 DB도 읽기 전용으로 엽니다. 서버에서 과거 기록을 가져오지는 않습니다.

## 기계 출력 계약

결과는 표준출력으로만 나갑니다. `send`, `notice`, `join`, `contact`, 첫 `auth`는 0.5초 넘게 걸리면 진행 단계와 경과 시간을 표준오류에 한 줄로 표시하고, 끝나면 그 줄을 지웁니다. `NO_COLOR`를 지정하면 색 없이 표시합니다. 표준오류가 터미널일 때만 표시하므로 파이프나 파일로 받으면 나오지 않습니다. `--json`(`notice`), `TERM=dumb`, `KKT_NO_PROGRESS=1`이면 터미널에서도 끕니다. PTY로 실행하며 화면 출력을 읽는 도구는 `KKT_NO_PROGRESS=1`을 지정하세요.

### `serve`: NDJSON

표준출력 한 줄에 JSON 객체 하나를 출력합니다. 모든 이벤트에는 `event`가 있습니다. 값이 `nil`인 선택 필드는 생략합니다.

| `event` | 필드(`event` 제외) |
|---|---|
| `message` | `logId`, `chatId`, `chatName`, `chatType`, `linkId`, `authorId`, `authorName`, `isFromMe`, `type`, `text`, `attachment`, `sentAt` |
| `heartbeat` | `maxLogId` |
| `error` | `reason` |
| `scrap` | `logId`, `chatId`, `attachment` |

`sentAt`은 유닉스 초, `attachment`는 원본 JSON을 담은 **문자열**입니다. 시작 커서를 생략하면 현재 최대 logId 이후부터 읽고, `--since-log-id`를 주면 해당 ID 이후를 읽습니다. 미전송 로컬 메시지(`logId = Int64.max`)는 출력·커서 전진 대상에서 제외합니다. `heartbeat`는 30초 간격이며 마지막 처리 커서를 전달합니다.

링크 미리보기는 메시지 시각부터 120초 동안 갱신을 확인해 `scrap`으로 알립니다. 앱이 미리보기를 받지 않으면 이벤트가 없을 수 있습니다. DB 오류는 재시도하며 연속 30회 발생하면 `error` 이벤트(`reason: "database_unavailable"`)와 종료코드 `1`로 끝납니다. 시작 시 설정·DB·간격 검증 실패는 이벤트 대신 `{"result":"failed","reason":"…"}` 한 줄을 반환합니다.

### 단일 결과와 읽기 JSON

`send`/`join`/`contact`는 `KktResult`의 한 줄 JSON을 반환합니다. 필드는 필수 `result`, 선택 `reason`, `chatId`, `logId`, `friendAdded`, `dryRun`, `imageRoute`이며 값이 없는 선택 필드는 생략합니다. `imageRoute`는 사진을 보낸 `send`에만 나오며 `background` 또는 `foreground`입니다. `dry_run`이라는 결과가 있어도 `dryRun` 필드가 반드시 존재하는 것은 아닙니다.

```json
{"result":"failed","reason":"chat_window_open"}
```

| 명령 | 가능한 `result` |
|---|---|
| `send` | `sent`, `uncertain`, `dry_run`, `failed` |
| `join` | `joined`, `requested`, `already_member`, `needs_password`, `full`, `ended`, `ineligible`, `dry_run`, `failed` |
| `contact` | `opened`, `already_contact`, `dry_run`, `failed` |
| `auth` | `ok`, `failed` |

`auth` 성공 필드는 `result`, `userId`, `database`(DB 파일명만)입니다. DB 키는 출력하지 않습니다. `uncertain`은 전송 또는 창 정리를 확정하지 못한 결과이므로 즉시 재전송하면 중복될 수 있습니다. `send`는 예외 발생 시 종료코드 `1`, `join`/`contact`는 `failed`일 때 `1`입니다. 그 외 결과는 종료코드 `0`일 수 있으므로 JSON도 함께 확인하세요.

`chats`/`messages`/`search`/`query`는 기본 표, `notice`는 메타데이터와 본문, `doctor`는 진단 표입니다. `--json`이면 다음 값을 한 줄로 출력합니다.

| 명령 | JSON 구조 |
|---|---|
| `chats` | 객체 배열: `id`, `type`, `display_name`, `member_count`, `last_message_at`, `unread_count` |
| `messages` / `search` | 객체 배열: `id`, `chat_id`, `sender_id`, `sender`, `text`, `type`, `timestamp`, `is_from_me` |
| `query` | 열 순서에 따른 행 배열의 배열(열 이름 제외) |
| `notice` | `chatId`, `text`, `source`, `truncated`, `updatedAt`(유닉스 초) |
| `doctor` | `executablePath`, `permissionNote`, `checks` 배열(`id`, `status`, `detail`, 선택 `fix`) |

읽기 JSON의 시각 문자열은 ISO 8601이고, 선택 필드의 `nil` 값은 생략합니다. 읽기 명령의 DB 오류는 한 줄 `failed` 결과를 반환하며, 일시 잠금은 최대 3회 시도한 뒤 `database_unavailable`로 끝납니다. 인자 파싱·검증 오류는 ArgumentParser의 표준 오류 안내가 나올 수 있습니다.

**ID는 JSON 숫자 그대로 출력합니다.** 2^53보다 큰 ID도 문자열로 바꾸지 않습니다. 소비자는 Swift `Int64` 또는 숫자 정밀도를 보존하는 JSON 파서를 사용하세요. JavaScript `JSON.parse`의 일반 `Number`로 읽은 뒤 문자열로 바꾸면 이미 정밀도가 손실될 수 있습니다.

### `reason` 코드

현재 `KktError`와 `KktConstants`에서 정의한 실패 코드입니다.

| 코드 | 의미·대응 |
|---|---|
| `chat_window_open` | 메인 창 외 카카오톡 창이 있어 UI 조작 거절. 사용자가 창을 닫은 뒤 재시도 |
| `kakaotalk_in_use` | 카카오톡이 전면 앱이라 UI 조작 거절. 다른 앱으로 전환한 뒤 재시도 |
| `kakaotalk_not_running` | 실행 중인 카카오톡 없음 |
| `read_only_sql` | 읽기 전용 SQL 제한 위반 |
| `input_locked` | 주의가 필요한 방 등에서 입력이 잠겨 있음 |
| `ambiguous_name` | UI 대상으로 해석한 방 이름이 중복됨 |
| `not_found` | 대상 방·공지·필수 로컬 정보 없음 |
| `busy` | 다른 작업이 잠금을 보유하거나 DB가 일시 잠김 |
| `automation_failed` | AX 화면·동작 확인 실패. `doctor`로 점검 |
| `database_unavailable` | DB 열기·조회 실패 또는 일시 잠금 재시도 한도 초과 |
| `invalid_link` | 지원하지 않는 참여 링크 |
| `invalid_profile` | 지원하지 않는 프로필 옵션 |
| `invalid_nickname` | 닉네임 누락·공백 등 유효성 오류 |
| `join_not_confirmed` | 참여 후 DB에서 방을 확인하지 못함 |
| `invalid_config` | 설정·환경변수 사용자 ID 또는 전송 시각 기록이 유효하지 않음 |
| `invalid_interval` | 폴링 간격이 유한한 양수가 아님 |
| `screen_recording_permission` | 화면 기록 권한 없음 |
| `screen_capture_failed` | 프로필 카드 화면 캡처 실패 |
| `card_not_visible` | 프로필 카드를 찾지 못함 |
| `button_not_found` | 프로필 카드 버튼을 찾지 못함 |
| `forbidden_label` | 신고·차단 등 금지된 버튼 감지 |
| `contact_window_not_found` | 1:1 채팅 창을 확인하지 못함 |
| `contact_not_confirmed` | 1:1 채팅 결과를 DB에서 확인하지 못함 |
| `encode_failed` | JSON 인코딩 실패 시 `KktOutput`의 대체 출력 |

실패 외에 `dry_run`의 `reason`은 확인 단계인 `cover`, `profile_choice`, `team_request`, `card_found:<버튼 이름>`일 수 있습니다. 내부 상수 `unexpected_window`는 예상과 다른 창 감지용이며, `KktError.automation`의 일반 코드로 변환되는 경로에서는 `automation_failed`로 출력됩니다. `messages`/`notice --chat`의 이름 미확정 결과는 reason 객체 대신 후보 배열과 종료코드 `2`를 반환합니다.

## 동작 규칙

- 기본 조작은 AX와 카카오톡 PID에 보내는 키 이벤트를 사용해 **백그라운드 우선**으로 수행합니다.
- 사진은 비공개 SkyLight API로 카카오톡을 앞으로 꺼내지 않고 붙여넣기를 먼저 시도합니다. 실패하면 카카오톡을 잠깐 앞으로 가져오는 기존 경로로 전환하고 결과의 `imageRoute`가 `foreground`가 됩니다.
- 메인 창이 최소화되거나 닫혀 있으면 `창 > 채팅` 메뉴를 AX로 눌러 앞으로 꺼내지 않고 표시합니다. 메뉴로 열지 못하면 `open -g`로 다시 여는데, 이때는 카카오톡이 잠깐 앞으로 나옵니다. `send`·`join`·`contact`와 `notice`의 화면 경로는 끝날 때 메인 창을 시작 전 상태로 되돌립니다.
- 전환된 사진 붙여넣기, 프로필 카드 버튼 클릭, 오픈채팅 링크 열기, 공지 배너 클릭은 잠깐 카카오톡을 앞으로 가져올 수 있습니다. 이때 카카오톡이 앞에 있으면 작업 시작 때의 앱으로 포커스를 복원합니다.
- UI 조작 시 메인 창 외 사용자 창이 있으면 거절합니다. **사용자가 연 창은 닫지 않고**, 같은 작업에서 kkt가 연 창만 정리합니다. 채팅 목록의 검색어·검색칸 표시 상태와 사진 붙여넣기에 사용한 클립보드를 복원합니다.
- 나와의 채팅은 **채팅 목록에 보이는 경우에만** 열 수 있습니다.
- 카카오톡이 전면에 있으면 PID 대상 키 입력이 한글 IME 조합에 섞일 수 있어 `kakaotalk_in_use`로 거절합니다. 다른 앱으로 전환한 뒤 실행하세요. DB 읽기는 이 UI 가드의 대상이 아닙니다.
- `contact`는 오픈채팅방의 화면에 있는 프로필 카드를 OCR로 찾습니다. 화면 크기·스크롤 위치·카드 표시 상태에 영향을 받습니다.
- 카카오톡 업데이트로 DB·AX 구조가 바뀔 수 있습니다. 로컬에 없는 메시지나 앱이 받지 않은 링크 미리보기는 제공하지 못합니다.

## 공지 읽기 규칙

`notice`는 최신 공지 메시지(type 24, 삭제 표시된 16408 포함)의 DB 본문을 우선합니다. 삭제 표시가 없고 490 UTF-16 코드 단위 미만이면 `source: "database"`, `truncated: false`입니다. 490 이상이거나, 최신 공지가 삭제 표시됐거나, DB에 공지 행이 없으면 **공지 배너 클릭 → 상세 화면의 AX 본문 읽기** 경로를 사용합니다. 성공하면 `source: "screen"`, `truncated: false`입니다. 공지 행이 없어 `updatedAt`을 알 수 없으면 `0`입니다. 댓글 입력칸과 등록 버튼은 조작하지 않습니다.

`source: "database"` 본문은 화면의 현재 공지와 다를 수 있습니다. 실측에서 DB 행과 화면 공지의 본문이 500자 안에서도 달랐고, 공지가 수정되면 DB 행이 갱신되지 않는 것으로 추정합니다.

사용자 창·카카오톡 사용 중·권한·잠금 등으로 화면 경로가 불가능하면 DB 미리보기를 `source: "truncated"`, `truncated: true`로 반환합니다. 이때도 종료코드는 `0`입니다. 삭제 표시된 공지가 이 결과로 나오면 현재 공지와 다를 수 있습니다. DB에 공지 행이 없을 때 화면 경로가 불가능하면 `chat_window_open` 같은 해당 사유로 실패합니다. DB에 행이 없고 화면에도 공지 배너가 없으면 `not_found`로 실패합니다. 공지 행이 없는 방은 확인을 위해 방을 한 번 열고 닫으므로 안 읽은 표시가 사라질 수 있습니다.
