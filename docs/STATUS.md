# JARVIS — S1 개발 상태 (2026-11-12)

## 기존 main 확인
- Python 기반 로컬 서버, 명시적 SQLite 기억, 규칙 기반 텍스트 명령.
- 브라우저 UI: 입자 원, 대시보드, 3개 사전 정의된 스타일, 화면 미리보기.
- SwiftUI 네이티브 셸: 화면 한 장 캡처, 한국어 TTS. 이전 GitHub macOS 컴파일 성공.
- 사용자 Mac Desktop Commander 장치는 마지막 확인 시 오프라인.

## feature/native-speech-s1 개발 중
- 명시적으로 켜는 한국어 온디바이스 음성 인식(Speech), 동의 기반 마이크 권한.
- 로컬 API 호출 뒤 검증된 응답을 자비스 UI로 반영.
- NSMicrophoneUsageDescription / NSSpeechRecognitionUsageDescription을 포함한 개발용 .app 패키징.
- workflow에서 Swift 컴파일뿐 아니라 패키징·Info.plist·코드서명 상태도 검사하도록 보강.

## 구현하지 않은 것
- 상시 호출어, LLM 판단, 실제 화면 AI 해석, Mac 자동 조작.
- 클라우드, iPhone, 자율 업무, 디자인 AI 생성.
- Mac 실기기 권한 동작은 GitHub Actions만으로 검증 불가.

## 바로 다음 검증
1. PR CI의 Python/JS/Swift/macOS 패키징이 통과하는지 확인.
2. 실제 Mac에서 `START_JARVIS_MAC.command`로 권한·마이크·화면 확인.
3. 이후 접근성 UI 구조를 읽는 **읽기 전용** 기능을 추가하고, LLM/행동 정책과 분리해 검증.
