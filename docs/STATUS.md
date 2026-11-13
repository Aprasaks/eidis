# JARVIS 개발 상태 — 2026-11-13

## main에 구현된 내용
- 미니멀 대기 화면/요청 시 프로젝트·기억·화면·디자인
- RAM 대화 맥락, 명시적 SQLite 기억과 프로젝트 상태 이력
- 공개 GitHub 읽기 전용 도구 실행/권한 확인/결과 증거 영수증
- Mac SwiftUI 음성·수동 화면·UI 구조 읽기 (CI 컴파일, 실기기 미검증)
- 외부 유료 모델은 기본 OFF

## 현재 PR: Mac readiness v1.5
- Mac 네이티브 진단 탭: 마이크·음성·온디바이스 한국어·화면 기록·접근성 권한 상태 조회
- 로컬 GET /api/diagnostics: 서버, SQLite quick_check, 프로젝트 수, 도구 허용 목록, 마지막 실행 영수증
- 진단 시 마이크·화면 켜기/권한 요청/GitHub·AI API 자동 호출 금지
- START_JARVIS_MAC.command에서 실제 HTTP 준비 확인 후 앱 실행
- GitHub 음성 조회의 네이티브 요청 타임아웃 확대

## 정확한 검증 경계
원격 Mac DECHIVE.local은 2026-11-13 확인 당시 오프라인이었습니다. 실제 음성 입력/응답·화면 캡처·GitHub 공개 API 실호출은 사용자 Mac에서 별도로 검증해야 합니다.
자세한 안내: docs/MAC_READINESS_V15.md