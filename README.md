# TokenJump

**AI와 작업한 만큼, 더 높이.**

TokenJump는 AI 코딩 도구의 토큰 사용량을 점프 에너지로 바꾸는 macOS 메뉴바 게임입니다. 작업하며 모은 점프로 발판을 오르고, 장애물을 피해 정상에 도전하세요.

## 다운로드 및 설치

**macOS 14 이상 · Apple Silicon Mac**이 필요합니다. 아래 두 배포 파일은 동일한 앱입니다. 릴리스의 **Assets**에서 원하는 형식을 선택하세요.

### DMG로 설치

1. [최신 릴리스](https://github.com/navyjeongs/TokenJump/releases/latest)에서 **TokenJump.dmg**를 다운로드하세요.
2. DMG를 열고 **Token Jump.app**을 옆의 **Applications** 폴더로 드래그하세요.
3. 복사가 끝나면 디스크 이미지를 추출하고, 응용 프로그램 폴더에서 **Token Jump**를 실행하세요.
4. macOS 상단 메뉴바의 게임 아이콘을 누르세요.

### ZIP으로 설치

1. [최신 릴리스](https://github.com/navyjeongs/TokenJump/releases/latest)에서 **TokenJump.zip**을 다운로드하세요. GitHub의 **Source code** 압축 파일은 실행 앱이 아닙니다.
2. 압축을 풀고 **Token Jump.app**을 **응용 프로그램(Applications)** 폴더로 옮기세요.
3. 앱을 실행한 뒤 macOS 상단 메뉴바의 게임 아이콘을 누르세요.

### 첫 실행이 차단될 때

현재 배포 앱은 Apple 공증을 받지 않았습니다. 다운로드 출처를 확인한 뒤 앱을 한 번 실행하고, **시스템 설정 → 개인정보 보호 및 보안 → 확인 없이 열기**를 선택하세요.

### 소스에서 빌드

Xcode Command Line Tools가 설치된 Mac에서 실행하세요.

```bash
git clone https://github.com/navyjeongs/TokenJump.git
cd TokenJump
./build-app.sh
open "dist/Token Jump.app"
```

배포용 ZIP·DMG와 SHA-256 체크섬 파일을 만들려면 `./package-release.sh`를 실행하세요. 결과는 `dist/`에 생성됩니다. GitHub Release에는 `TokenJump.zip`, `TokenJump.dmg`, `SHA256SUMS.txt`를 첨부합니다.

## 작업하고, 모으고, 도약하세요

Codex와 Claude Code의 로컬 사용 기록을 읽어 점프 에너지를 충전합니다. 메뉴바 아이콘을 누르면 게임이 바로 열리고, 사용량 탭에서 남은 점프와 토큰 기록을 확인할 수 있습니다.

처음 시작하면 **보너스 점프 30회**를 받습니다. 게임을 닫으면 진행 중인 플레이는 일시 정지되어, 잠깐 쉬었다가 다시 이어갈 수 있습니다.

## 세 가지 난이도, 각각 20스테이지

- **보통:** 넓은 발판에서 시작해 새로운 장애물을 하나씩 익혀갑니다.
- **어려움:** 첫 스테이지부터 정밀한 착지와 빠른 판단이 필요합니다.
- **하드코어:** 어려움 후반 수준의 20개 코스에 도전합니다. 첫 점프 후 천천히 추적하는 유령은 접촉하면 첫 발판으로 돌려보냅니다. 후반으로 갈수록 발판이 좁아지고 유령이 빨라집니다.

좌우·상하 이동 발판, 미끄러운 빙판, 사라지거나 무너지는 발판을 건너보세요. 회전 가시와 대포를 피하고, 바람을 버티며, 스위치로 길을 열고 열쇠를 모아 골인하세요.

현재 스테이지를 클리어하면 다음 스테이지가 열립니다. 떨어지면 해당 스테이지의 첫 발판부터 다시 도전합니다. 난이도는 도전을 시작하기 전에 선택하고, 20스테이지를 모두 클리어하면 바꿀 수 있습니다.

## 간단한 조작

| 키 | 동작 |
|---|---|
| A / D 또는 ← / → | 이동 |
| Space / W / ↑ | 점프 |
| R | 현재 스테이지 다시 시작 |
| N / Enter | 클리어 후 다음 스테이지 |
| Esc | 게임 닫기 |

## 지원 환경

**macOS 14 이상**에서 사용할 수 있습니다. Codex·Claude Code의 로컬 토큰 기록을 지원하며, 웹 채팅 사용량은 집계하지 않습니다. 최초 실행 이후 새로 기록된 사용량부터 반영합니다.

[GitHub Releases](https://github.com/navyjeongs/TokenJump/releases) · [사용 서체 및 라이선스](THIRD_PARTY_NOTICES.md)
