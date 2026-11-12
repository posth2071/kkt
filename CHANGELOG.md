# 변경 기록

## Unreleased

- `notice`가 공지 아래 댓글도 읽어 `comments`(위에서부터 순서대로)로 반환. 댓글이 화면 아래에 있으면 공지 창을 내려 가며 모으고 끝나면 맨 위로 되돌림. 댓글이 없거나 DB 본문으로 돌아갈 때는 `comments` 키를 내보내지 않아 기존 JSON 계약 유지. 텍스트 출력에는 `[댓글]` 아래 한 줄씩 덧붙임. `NoticeAX.readScreen`·`NoticeScreen`·`NoticeReader(fetch:screenWithComments:)` 추가.
- `notice`가 490자 미만 공지도 화면에서 읽도록 수정. 공지를 수정해도 DB 행이 갱신되지 않아 예전 내용이 나오던 문제 해결. 이제 호출마다 방을 열고 카카오톡이 잠깐 앞으로 오며, 화면을 읽지 못하면 DB 본문을 `source: "truncated"`, `truncated: true`로 반환. `NoticeReader.read`는 `source: "database"`를 반환하지 않음.
- 안드로이드 에뮬레이터처럼 번들 ID가 없는 앱이 앞에 있을 때 작업 뒤 포커스가 카카오톡에 남던 문제 수정. `FocusGuard`가 프로세스로 복원하고, 공개 생성자에 선택 인자 `captureProcess`·`activate` 추가.

## v0.2.0 — 2026-11-05

- `kkt --version` 추가. 터미널에서는 카카오톡·macOS 버전과 실행 파일 경로를 함께 표시하고, 파이프에서는 이름과 버전 한 줄만 출력.
- `send`·`notice`·`join`·`contact`·첫 `auth`가 0.5초 넘게 걸리면 터미널에 진행 단계와 경과 시간을 색으로 표시(`NO_COLOR` 지원). 표준오류가 터미널일 때만 나오고 끝나면 지워지며, 표준출력의 결과는 그대로. `--json`(`notice`), `TERM=dumb`, `KKT_NO_PROGRESS=1`로 끌 수 있음. `SendOperation.execute`에 선택 인자 `progress` 추가.
- `send`에 `--via-card-room`·`--via-card-user`·`--via-card-nickname` 선택 옵션 추가. 1:1 방의 이름 검색 실패 시 기존 프로필 카드 흐름으로 방 열기.
- 카드 전송 전 직접방 구성원 ID·DB 방 이름·최근 메시지의 AX 본문 대조로 대상 확인. 실패 시 전송 없이 창 정리, 기존 JSON 필드 유지.
- `send --image`가 비공개 SkyLight API로 카카오톡을 앞으로 꺼내지 않고 사진을 붙여넣도록 변경. 실패하면 기존 전면 경로로 전환하고, 결과에 `imageRoute`(`background`/`foreground`)를 추가. `doctor`에 `image_background` 항목 추가.
- 메인 창이 최소화된 상태의 `automation_failed`와 닫힌 상태의 전면 노출을 수정. `창 > 채팅` 메뉴로 표시하고, 끝나면 시작 전 창 상태로 복원.
- 포커스 복원이 카카오톡이 앞에 있을 때만 동작하도록 수정. 이전에는 kkt가 방을 열 때마다 시작 시점의 앱을 다시 활성화해, 실행 중 다른 앱으로 옮긴 사용자를 끌어왔음.
- `notice`가 삭제 표시된 공지 메시지(type 16408)를 인식하고, 이 경우와 DB에 공지 행이 없는 경우 화면 공지를 읽도록 수정. 공지 행이 없을 때 화면 경로가 막히면 `not_found` 대신 실제 사유 반환.

## v0.1.0 — 2026-11-03

- macOS 14 이상·Swift 6용 `KktCore` 라이브러리와 `kkt` CLI 제공.
- 본인 계정의 로컬 사용자 ID 복구, DB 키 계산, 읽기 전용 SQLCipher 연결과 설정 저장.
- 채팅 목록·메시지·본문 검색·읽기 전용 SQL 조회.
- 메시지·하트비트·오류·링크 미리보기 갱신을 전달하는 `serve` NDJSON 스트림과 Int64 ID 보존.
- 백그라운드 AX 기반 글·사진 전송, DB 전송 확인과 dry-run.
- 오픈채팅 참여·팀채팅 참여 요청, 프로필 카드 OCR을 통한 친구 추가·1:1 채팅 열기.
- DB 우선 공지 읽기, 긴 공지의 AX 화면 보완과 잘림 상태 반환.
- 사용자 창·전면 사용 가드, 검색 텍스트·클립보드·포커스 복원, 파일 잠금과 최소 전송 간격.
- 권한·DB·앱 버전·AX 구조를 검사하는 `doctor`와 카카오톡 26.9 검증 기록.
- 기본 `~/.local/bin/kkt` 설치 스크립트, 라이브러리·유지보수 문서와 개인정보를 제거한 픽스처.
