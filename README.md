<p align="center"><img src="Resources/AppIcon.png" width="128" alt="LidOn"></p>

<h1 align="center">LidOn</h1>

<p align="center"><b>맥북 뚜껑을 닫아도 코딩 에이전트와 작업이 계속 돌아가게 해 주는 무료 메뉴 막대 앱</b><br>
Claude Code · Codex · Cursor · 빌드 · 다운로드 — 외부 모니터나 충전기 없이</p>

<p align="center"><a href="README.en.md">English</a></p>

<p align="center">
  <img src="docs/screenshots/menu.png" width="330" alt="Menu">
  &nbsp;
  <img src="docs/screenshots/welcome.png" width="330" alt="Welcome">
</p>
<p align="center">
  <img src="docs/screenshots/overlay-fn.jpg" width="680" alt="Hold Fn and close the lid">
</p>

---

## 특징

| | LidOn |
|---|---|
| 가격 | **무료, 오픈 소스 (MIT)** |
| Fn(🌐)을 누른 채 뚜껑 닫기 | ✅ 전체 화면 애니메이션으로 확인 |
| **AI 에이전트가 직접 켜고 끄기** (MCP · Claude Code 플러그인/스킬) | ✅ 사유·시간 지정, 끝나면 잠자기 |
| 수동 토글 (끌 때까지 / 30분~8시간) | ✅ |
| 발열 · 배터리 온도 · 배터리 잔량 보호 | ✅ 한계값 조절 가능 |
| 최대 실행 시간 / 타이머 | ✅ |
| **앱이 죽거나 멈춰도 잠자기 자동 복구 (워치독)** | ✅ |
| **휴대폰 알림** (ntfy · Slack · Discord · 웹훅) | ✅ |
| **터미널 명령어** `lidon run -- npm test` | ✅ 명령이 끝나면 잠자기 |
| 전역 단축키 ⌃⌥⌘L, URL 스킴 `lidon://on` | ✅ |
| 세션 기록과 배터리 소모 통계 | ✅ |
| sudo / 관리자 권한 | 필요 없음 |
| 한국어 · 영어 | ✅ |

## 설치

**설치 스크립트 (권장)**

```bash
curl -fsSL https://raw.githubusercontent.com/echod3v/LidOn/main/install.sh | bash
```

`/Applications`에 설치하고 `lidon` 명령어를 연결한 뒤 실행해요.

**Homebrew**

```bash
brew install --cask echod3v/tap/lidon
```

**직접 다운로드**

[Releases](https://github.com/echod3v/LidOn/releases)에서 `LidOn-x.y.z.zip`을 받아 압축을 풀고 응용 프로그램 폴더로 옮기세요.
LidOn은 Apple 개발자 서명이 없는 무료 앱이라 처음 열 때 경고가 떠요. 아래 둘 중 하나로 허용하세요.

- **시스템 설정 → 개인정보 보호 및 보안** 아래쪽에서 **"그래도 열기"** 클릭
- 또는 터미널에서: `xattr -dr com.apple.quarantine /Applications/LidOn.app`

요구 사항: macOS 14 Sonoma 이상, 뚜껑이 있는 MacBook (Apple Silicon · Intel)

## 사용법

| 방법 | 동작 |
|---|---|
| **Fn(🌐)을 누른 채 뚜껑 닫기** | 0.5초 이상 누르면 화면에 안내가 뜨고, 그 상태로 닫으면 계속 실행 |
| **에이전트의 요청** | 에이전트가 `keep_awake`를 부르면 준비돼요 (아래 참고) |
| **메뉴 막대 → 뚜껑 닫아도 계속 실행** | 끌 때까지 또는 30분~8시간 동안 |
| **⌃⌥⌘L** | 어디서든 켜고 끄기 |
| **터미널** | 아래 참고 |

뚜껑을 닫으면 화면이 잠기고 디스플레이가 꺼져요. 다시 열면 평소 잠자기 설정으로 돌아가요.
뚜껑이 닫혀 있는 동안 에이전트가 요청을 풀거나, 명령이 끝나거나, 안전장치가 작동하면 Mac이 스스로 잠들어요.
Fn으로 닫았거나 수동 토글을 켰다면 뚜껑을 열 때까지(또는 끌 때까지) 유지돼요.

### 터미널 명령어

```bash
lidon run -- npm test                      # 명령이 실행되는 동안만 켜 두고, 끝나면 잠자기
lidon keep --for 2h --reason "데이터 이전"   # 2시간 동안 켜 두기 → id 출력 (최대 12시간)
lidon release <id>                         # 다시 잠들 수 있게
lidon wait 12345                           # PID 12345 프로세스가 끝날 때까지 켜 두기
lidon notify "빌드 끝남"                    # Mac + 휴대폰 알림
lidon on --for 2h / lidon off              # 수동 토글
lidon status [--json]
```

`lidon`은 설치 스크립트나 Homebrew가 연결해 줘요. 직접 설치했다면 **설정 → 정보 → lidon 명령어 설치**를 누르세요.

URL 스킴: `open "lidon://on?for=90m"`, `lidon://off`, `lidon://toggle` (단축어 앱이나 Raycast에서 쓸 수 있어요)

### AI 에이전트 연결

LidOn은 에이전트가 일하는지 추측하지 않아요. 대신 **에이전트가 직접** "깨워 둬"라고 요청하고, 끝나면 풀어요.
에이전트는 MCP 도구 네 개를 받아요.

| 도구 | 하는 일 |
|---|---|
| `keep_awake(reason, minutes)` | 사유와 시간(기본 60분, 최대 12시간)을 걸고 Mac을 깨워 둬요 |
| `allow_sleep()` | 요청을 풀어요. 뚜껑이 닫혀 있으면 Mac이 잠들어요 |
| `lidon_status()` | 뚜껑, 배터리, 온도, 활성 요청을 알려 줘요 |
| `notify(message)` | Mac과 휴대폰으로 알려요 |

요청은 에이전트가 `allow_sleep`을 부르거나, 시간이 지나거나, **에이전트 세션이 끝나면(크래시 포함) 자동으로** 풀려요.
메뉴 막대에서 요청을 직접 취소할 수도 있어요.

**Claude Code — 플러그인 (MCP + 스킬)**

```
/plugin marketplace add echod3v/LidOn
/plugin install lidon@lidon
```

스킬이 Claude에게 언제 `keep_awake`/`allow_sleep`을 써야 하는지 알려 줘요.

**한 번에 연결 (Claude Code · Codex · Cursor)**

```bash
lidon setup claude     # MCP 서버(user scope) + 스킬 + LidOn 도구 자동 허용(mcp__lidon)
lidon setup codex      # ~/.codex/config.toml 에 [mcp_servers.lidon] + 스킬(~/.agents/skills/lidon)
lidon setup cursor     # ~/.cursor/mcp.json
lidon setup --print    # 파일을 바꾸지 않고 설정 조각만 출력
```

연결하면 에이전트는 약 5분 이상 걸릴 작업 전에 **묻지 않고 알아서** `keep_awake`를 걸고, 끝나면 풀어요.
Claude Code에서는 LidOn 도구 4개만 승인 없이 쓰도록 허용해요 (`lidon run`으로 감싼 셸 명령은 평소처럼 승인을 받아요).

앱의 **설정 → 에이전트**에서도 버튼으로 연결할 수 있어요. 바꾸는 파일은 `.lidon-backup`으로 백업돼요.
다른 MCP 클라이언트는 `lidon mcp`를 stdio 서버로 등록하면 돼요.

MCP를 쓰지 않는 에이전트는 `lidon agent-docs` 출력을 프로젝트의 `CLAUDE.md`나 `AGENTS.md`에 붙여 넣으세요.
에이전트가 `lidon run -- <명령>`, `lidon keep`, `lidon notify`를 쓰게 돼요.

### 휴대폰 알림

**설정 → 알림**에서 서비스를 고르세요. 가장 쉬운 건 [ntfy](https://ntfy.sh)예요.

1. 휴대폰에 ntfy 앱을 설치하고, 남들이 추측하기 어려운 토픽(예: `lidon-a8f3k2`)을 구독해요.
2. LidOn에서 서비스를 **ntfy**로 고르고 URL에 `https://ntfy.sh/lidon-a8f3k2`를 넣어요.
3. **테스트 보내기**로 확인해요.

에이전트가 `notify`를 부를 때, 그리고 요청이 끝나거나 안전장치가 작동해서 Mac이 잠들기 직전에 알림을 보내요.
잠들기 전에는 전송을 위해 최대 6초 기다려요.

## 안전

- **발열 보호**: macOS 발열 상태가 '높음' 이상이거나 배터리 온도가 한계(기본 45°C)에 이르면 잠자기
- **배터리 보호**: 전원이 연결되지 않은 상태에서 배터리가 기본 10% 이하이면 잠자기
- **워치독**: LidOn이 강제 종료·크래시·멈춤 상태가 되거나 Mac 온도가 '위험' 단계에 이르면, 별도 감시 프로세스가 잠자기 설정을 즉시 되돌려요. 이 동작은 안전장치 설정과 관계없이 항상 켜져 있어요.
- 뚜껑이 닫힌 Mac을 **가방 안에서 실행하지 마세요.** 단단하고 트인 곳에 두세요. 오래 걸리는 작업은 충전기 연결을 권장해요.

워치독이 복구한 기록은 `~/Library/Application Support/LidOn/watchdog.log`에 남아요.

## 동작 원리

- 커널의 `IOPMrootDomain`에 비공개 selector `kPMSetClamshellSleepState`(12)를 호출해서 뚜껑을 닫아도 잠들지 않게 해요. `pmset disablesleep`과 달리 root 권한이 필요 없어요.
- 이 커널 상태는 호출한 프로세스가 죽어도 **그대로 남아요.** 그래서 LidOn은 자기 자신을 `--watchdog` 모드로 한 번 더 실행하고 파이프로 하트비트를 보내요. 파이프가 끊기거나 하트비트가 30초 넘게 없으면 워치독이 상태를 되돌려요.
- macOS 전원 데몬(powerd)도 같은 비트를 쓰기 때문에(외부 디스플레이 연결/해제 등) 켜져 있는 동안 1초마다 다시 적용해요.
- 뚜껑 열림/닫힘은 IOKit 알림으로 즉시 받아요. 뚜껑이 닫혀 있는 동안에는 빠른 폴링을 멈춰서 전력을 아껴요.
- 에이전트 연동은 `lidon mcp`(의존성 없는 Swift stdio MCP 서버)가 앱에 요청을 보내는 방식이에요. 요청은 MCP 서버 프로세스에 묶여 있어서 에이전트가 끝나면 앱이 즉시 알아채요.
- 상태 머신(`Sources/LidOnCore/Engine.swift`)은 시스템 호출 없는 순수 로직이라 단위 테스트로 검증해요.

⚠️ 공개되지 않은 macOS 인터페이스를 사용하므로 macOS를 크게 업데이트한 뒤에는 한 번 다시 테스트해 주세요.

## 소스에서 빌드

```bash
swift test                          # 단위 테스트
scripts/build-app.sh                # build/LidOn.app (유니버설)
ARCHS=arm64 scripts/build-app.sh    # 현재 아키텍처만 (빠름)
open build/LidOn.app
```

Xcode 16 이상(Swift 6 툴체인)이 필요해요.

## 배포 (관리자용)

1. `scripts/set-repo.sh 내아이디/LidOn` — 저장소 이름을 모든 파일에 반영
2. `git tag v1.0.0 && git push origin v1.0.0` — GitHub Actions가 테스트 → 유니버설 빌드 → Release 생성까지 해요
3. Homebrew: `내아이디/homebrew-tap` 저장소를 만들고, 릴리스에 첨부된 `lidon.rb`를 `Casks/lidon.rb`로 올려요

로컬에서 만들려면 `scripts/release.sh 1.0.0`을 실행하세요 (`dist/`에 zip, sha256, cask가 생겨요).
Apple Developer ID가 생기면 `SIGN_ID="Developer ID Application: …" scripts/build-app.sh`로 정식 서명할 수 있어요.

## 라이선스

MIT
