# EIDIS / JARVIS

개인용 JARVIS의 초기 프로토타입입니다. **아직 완성된 AI 비서가 아닙니다.**

- `app.py` / `jarvis/`: Python localhost 서버, 규칙 기반 명령, 명시적 SQLite 기억
- `web/`: 입자 호출 → 은은한 작업 공간 전환, API 기반 현황, 4개 사전 제작 디자인 시안의 미리보기/적용/되돌리기
- `jarvis/design.py`: 자연어에 맞춘 로컬 디자인 토큰 조합, 선택적으로 실행하는 외부 AI 구조화 설계 어댑터
- `macos/`: SwiftUI 네이티브 창, 한국어 음성 출력, ScreenCaptureKit 1장 미리보기
- `tests/`: 자동 검증
- `.github/workflows/ci.yml`: Linux 코드 검증 + macOS Swift 컴파일

## 실행 (Mac)

**쉬운 실행:** macOS 14 이상이고 Xcode Command Line Tools와 Python 3가 준비돼 있다면 `START_JARVIS_MAC.command`를 더블클릭합니다. 서버와 네이티브 셸을 함께 시작합니다. 최초에는 macOS 보안 확인이 필요할 수 있습니다. 네이티브 화면 캡처는 시스템 권한 허용 후 직접 버튼으로 시작하세요.

**브라우저만 실행:** `START_JARVIS.command`를 더블클릭하거나 `python3 app.py` 실행. 브라우저에서 `http://127.0.0.1:8765`.

**개발자 테스트:** `python3 -m unittest discover -s tests -v`; `swift build --package-path macos`.

## 로컬 화면 글자 읽기 v1.8

Mac 앱 **화면** 탭에서 명시적으로 **화면 캡처 + 글자 읽기**를 누르면 Apple Vision을 이용해 한국어/영어 텍스트를 기기 내에서 인식하고 표시합니다. 자비스 자신의 창은 캡처에서 제외합니다. **외부 전송, 자동 기록, AI 이미지 이해는 없습니다.** 실제 Mac 화면 권한과 실캡처 성공은 앱에서 별도 승인·확인이 필요합니다. 자세히: docs/SCREEN_TEXT_V18.md.

## 현재 한계

- 자연어 LLM 분석, AI 화면 이해, Mac 앱 조작, 웨이크워드 상시 감지, iPhone·클라우드 연결은 **미구현**.
- macOS 네이티브 셸은 GitHub Actions에서 **컴파일 테스트**만 했으며 사용자 Mac의 권한·UI 실행은 별도로 검증해야 합니다.
- ScreenCaptureKit은 명시적으로 버튼을 눌러 1장을 캡처하고 미리보기만 제공하며 파일·외부 AI로 보내지 않습니다.
- 브라우저 Web Speech 음성 인식은 브라우저 공급자의 원격 처리가 포함될 수 있습니다.
- GitHub Actions는 테스트만 실행하고 자동 배포나 시스템 변경을 하지 않습니다.

자세한 기술 설계: `docs/ARCHITECTURE.md`; 디자인 생성과 API 동의: `docs/DESIGN_STUDIO_V07.md`; macOS 실행: `macos/README.md`.


## Read-only vision (v0.9)
사용자가 선택한 화면의 한 장을 **별도 동의가 있을 때만** 외부 AI 모델로 분석하는 경로가 추가되었습니다. 기본 OFF, 별도 API 사용료, 로컬 미리보기는 무료. 사용법·정보보호: `docs/VISION_V09.md`. 실제 Mac 권한과 유료 API 실호출은 미검증입니다.


## JARVIS CONSOLE v1.0
데스크톱 오른쪽(모바일은 하단 접이식)에 명령·로컬 활동·연결 오류를 모아 표시합니다. 중앙 작업 화면에 흩어졌던 활동 로그를 제거했습니다. **운영체제의 셸 로그는 수집하지 않습니다.** 자세한 범위: `docs/CONSOLE_V10.md`.


## 대화 맥락 / Brain v1.2
입력창과 Mac 음성 인터페이스가 공통 대화 API를 이용합니다. **이 실행 중의 최근 대화**를 RAM에서 유지하며, 명시적으로 저장한 SQLite 기억만 검색합니다. 기본적으로 LLM 추론은 비활성화이며, 별도 API 키·모델 지정·서버 허용·매 요청 동의가 있을 때만 유료 텍스트 모델 응답을 사용합니다. 실제 API 실호출은 별도 검증 대상입니다. 자세히: `docs/CONTEXT_BRAIN_V12.md`.


## Project Ledger v1.3
프로젝트/할 일/진행·막힘·완료를 사용자가 직접 기록하고 영구적으로 관리합니다. GitHub 확인은 **공개 저장소에 한해 버튼을 눌렀을 때만** 실행하며, 확인 시각과 실제 커밋/Workflow 증거를 작업 상태와 분리합니다. 자동 완료 판단이나 외부 API 과금은 하지 않습니다. 상세: docs/PROJECT_LEDGER_V13.md.


## Tools v1.4 — 읽기 전용 업무 실행
등록된 공개 GitHub 프로젝트에 대해 **명시적인 상태 확인 요청**이 오면, 허용 도구로 브랜치 HEAD·현재 SHA의 일부 Workflow를 읽고 실행/오류 기록을 남깁니다. 한 서버 실행당 최대 8회 조회, 무단 배포·수정·삭제 도구 없음. 별도 AI 요금 없음. 실제 사용자 Mac의 GitHub 인증/비공개 저장소 접근은 미구현. 자세히: docs/TOOLS_V14.md.


## Mac 실기기 진단 v1.5
앱의 진단 탭에서 버튼을 눌러 Mac 권한 상태·localhost 서버·SQLite 읽기·등록 도구 상태를 권한 요청이나 외부 API 호출 없이 확인할 수 있습니다. START_JARVIS_MAC.command는 서버 HTTP 준비를 확인한 다음 앱을 열도록 변경했습니다. 실제 마이크·화면·GitHub 조회 성공은 사용자 Mac에서 각각 수동 시험해야 합니다. 상세: docs/MAC_READINESS_V15.md.


## Mac 음성 출력 설정
Mac 앱의 음성 탭에서 **설치된 한국어 목소리 선택, 속도/음높이 조절, 미리 듣기**가 가능합니다. 설정은 UserDefaults에 보존되며 모든 네이티브 음성 응답에 동일하게 적용합니다. 별도 유료 TTS API 호출 없음. 자세히: docs/VOICE_SETTINGS_V16.md.


## ElevenLabs 선택 음성 (기본 OFF)
Mac 앱 음성 탭에서 제공받은 Voice ID를 기본 입력하고, macOS 키체인에 API 키를 직접 저장하면 ElevenLabs 미리 듣기와 유료 음성 출력을 선택적으로 활성화할 수 있습니다. API 키를 저장해도 자동 호출하지 않으며 5회/실행·600자/응답 제한과 Mac 기본 음성 대체 기능이 적용됩니다. 앱에서 실제 유료 요청을 아직 시험하지 않았습니다. 상세: docs/ELEVENLABS_V17.md.
