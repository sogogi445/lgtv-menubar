# LG TV 메뉴 막대 앱

[English](README.md) | **한국어**

맥 **메뉴 막대**에서 같은 네트워크의 LG webOS TV를 조작하는 작은 앱입니다.

> 비공식 프로젝트입니다. LG Electronics와 관련이 없으며, "LG", "webOS"는 각 소유자의 상표입니다.

## 기능

- 전원 켜기(Wake-on-LAN) / 끄기
- 볼륨 +/−, 음소거
- 채널 목록(TV에서 읽어 옴), 다음/이전 채널
- 입력 전환(HDMI 1~3, AV, 컴포넌트)
- 리모컨 키: 홈, 뒤로, 확인, 방향키, 나가기
- TV 자동 탐색(SSDP) - IP/MAC을 직접 입력할 필요 없음. IP가 바뀌어도 MAC으로 다시 찾음
- 메뉴 언어: **English(기본)** 또는 **한국어** (메뉴 막대 아이콘 → *언어*)
- 로그인 시 자동 실행 옵션, Dock 아이콘 없음
- 분석/추적 없음, 외부 서버 통신 없음: 같은 네트워크의 TV와만 통신합니다

## 요구 사항

- macOS 13 이상 (Apple silicon · Intel)
- LG webOS TV (webOS 4.5에서 확인. webOS 3~6 계열은 같은 프로토콜을 씁니다)
- 맥과 TV가 같은 네트워크
- *전원 켜기*는 Wake-on-LAN을 씁니다. 테스트한 TV(webOS 4.5)에서는 **설정을 바꾸지 않아도** 켜졌습니다. 안 켜지는 TV라면 설정에서 **Wake on LAN / LG Connect Apps / Quick Start+** 를 켜 보세요

## 설치

**방법 1 - 릴리스 다운로드:** [Releases](../../releases)에서 `LG-TV.dmg`(또는 `LG-TV.zip`)를 받아 `LG TV.app`을 응용 프로그램 폴더로 옮깁니다.
Apple 공증을 받지 않은 앱(임시 서명)이라 처음 열 때 경고가 뜹니다 → 앱을 **우클릭 → 열기**,
또는 시스템 설정 → 개인정보 보호 및 보안 → "그래도 열기", 또는

```sh
xattr -dr com.apple.quarantine "/Applications/LG TV.app"
```

**방법 2 - 직접 빌드:** Xcode 명령줄 도구(`xcode-select --install`)만 있으면 됩니다.

```sh
git clone https://github.com/sogogi445/lgtv-menubar.git && cd lgtv-menubar
./build.sh                       # build/LG TV.app (Apple silicon + Intel 겸용)
cp -R "build/LG TV.app" /Applications/
```

## 처음 사용

1. 앱을 열면 메뉴 막대에 TV 아이콘이 생깁니다. **TV를 켠 상태에서** 아이콘을 누르세요.
2. 앱이 TV를 자동으로 찾습니다. macOS가 **로컬 네트워크** 접근을 물으면 허용하세요.
3. **TV 화면에 "연결 허용" 팝업**이 뜨면 TV 리모컨으로 허용하세요. (맥마다 한 번)
4. 이후엔 TV가 꺼져 있어도 *전원 켜기*를 쓸 수 있습니다. TV의 MAC 주소는 처음 연결될 때 자동으로 저장됩니다.

다른 TV로 바꿨다면 메뉴의 **TV 다시 찾기**를 누르세요.

## 문제 해결

| 증상 | 확인할 것 |
|---|---|
| "TV를 찾지 못했습니다" | TV가 켜져 있고 같은 Wi-Fi/공유기인지, 로컬 네트워크 권한(시스템 설정 → 개인정보 보호 및 보안 → 로컬 네트워크)이 허용인지 |
| *전원 켜기*가 안 됨 | TV가 콘센트가 뽑힌 상태가 아닌 대기 상태인지. MAC을 아직 모르면 TV를 켠 채로 메뉴를 한 번 여세요. TV에 따라 설정에서 **Wake on LAN / LG Connect Apps / Quick Start+** 를 켜야 할 수도 있습니다 |
| 계속 허용 팝업이 뜸 | 페어링 정보가 사라진 경우입니다. 앱 설정을 지우고 다시 페어링: `defaults delete dev.lgtvmenubar.app` |
| 채널 목록이 비어 있음 | TV가 켜져 있을 때 TV에서 불러옵니다. TV를 켠 상태에서 메뉴를 여세요 |

수동 설정(자동 탐색이 안 될 때만):

```sh
defaults write dev.lgtvmenubar.app ip  "TV의_IP"
defaults write dev.lgtvmenubar.app mac "TV의_MAC"
```

## 동작 방식

- TV의 `wss://<tv-ip>:3001`에 webOS **SSAP** 웹소켓으로 접속해 등록(페어링)하고 `ssap://audio/volumeUp`, `ssap://tv/openChannel` 같은 명령을 보냅니다.
  TV 인증서는 자체 서명이라 이 연결에 한해 인증서 검증을 건너뜁니다.
- 리모컨 키(홈/뒤로/방향키)는 TV가 알려주는 포인터 입력 소켓으로 보냅니다.
- *전원 켜기*는 **Wake-on-LAN** 매직 패킷(UDP 9/7)입니다. TV가 꺼지면 웹소켓이 닫혀서 API로는 켤 수 없습니다.
- TV 탐색은 SSDP `urn:lge-com:service:webos-second-screen:1` 검색이고, MAC 주소는 ARP 테이블에서 읽습니다.

## 보안·개인정보

- 페어링 키는 이 맥의 앱 설정(UserDefaults, `dev.lgtvmenubar.app`)에만 저장됩니다. 저장소나 앱 파일에는 들어 있지 않습니다.
  키를 가진 사람은 같은 네트워크에서 TV를 조작할 수 있으니 공유하지 마세요.
- 분석/추적이 없고, TV 외에는 어디에도 접속하지 않습니다.

## 언어 추가

기본 언어는 영어입니다. 언어를 추가하려면 `res/en.lproj`를 `res/<코드>.lproj`로 복사해 `Localizable.strings`의 오른쪽(번역문)을 바꾸고
(왼쪽 영어 문장은 찾기용 키입니다), `Info.plist`의 `CFBundleLocalizations`와 `src/main.swift`의 *언어* 메뉴에 추가하세요.

## 개발

```sh
./tools/run_tests.sh   # 가짜 로컬 서버(127.0.0.1)로 시험합니다. 실제 TV에는 아무것도 보내지 않습니다.
                       # python3와 `pip install websockets`가 필요합니다 (PYTHON=... 으로 파이썬 지정)
```

- `src/main.swift` - 앱 전체(AppKit, 외부 의존성 없음)
- `res/` - 등록 매니페스트와 번역
- `tools/` - 가짜 TV/SSDP 서버, 시험 스크립트

## 라이선스

MIT - [LICENSE](LICENSE). 서드파티 고지는 [NOTICE](NOTICE)를 참고하세요.
