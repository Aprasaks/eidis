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

## 현재 한계

- 자연어 LLM 분석, AI 화면 이해, Mac 앱 조작, 웨이크워드 상시 감지, iPhone·클라우드 연결은 **미구현**.
- macOS 네이티브 셸은 GitHub Actions에서 **컴파일 테스트**만 했으며 사용자 Mac의 권한·UI 실행은 별도로 검증해야 합니다.
- ScreenCaptureKit은 명시적으로 버튼을 눌러 1장을 캡처하고 미리보기만 제공하며 파일·외부 AI로 보내지 않습니다.
- 브라우저 Web Speech 음성 인식은 브라우저 공급자의 원격 처리가 포함될 수 있습니다.
- GitHub Actions는 테스트만 실행하고 자동 배포나 시스템 변경을 하지 않습니다.

자세한 기술 설계: `docs/ARCHITECTURE.md`; 디자인 생성과 API 동의: `docs/DESIGN_STUDIO_V07.md`; macOS 실행: `macos/README.md`.
