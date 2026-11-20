# JARVIS v3.13.1 — 자연어 요청형 실시간 로컬 대시보드

## 목표

기본 JARVIS는 언제나 기존 금빛 코어이며, 여러 버튼을 누르는 GUI가 아니다. 사용자가 자연어로 요청한 경우에만 오른쪽에 적절한 정보 패널을 띄운다. 브라우저 검색 결과가 모든 질문의 기본 대답이 되어서는 안 된다.

## 이번 버전에서 실제 연결한 데이터

| 음성/텍스트 요청 예시 | 대시보드 종류 | 실제 조회 출처 |
|---|---|---|
| `전체 대시보드 띄워줘` | LIVE OVERVIEW | `/api/projects`, `/api/vault`, `/api/diagnostics`, `/api/status`, Ollama `/api/version` |
| `프로젝트 현황 보여줘` | PROJECT INTELLIGENCE | JARVIS 로컬 SQLite `/api/projects` |
| `저장한 자료 분석해 줘` | KNOWLEDGE ARCHIVE | JARVIS 로컬 SQLite `/api/vault?limit=12` |
| `자비스 시스템 상태 보여줘` | SYSTEM TELEMETRY | 로컬 서버 진단/상태 + Ollama 버전 |
| `대시보드 닫아` 또는 현재 패널을 두고 `그거 닫아` | 화면 숨김 + 갱신 중단 | 추가 요청 없음 |

- `JarvisLiveDashboardIntent`: 동작과 데이터 소스가 명확한 질문만 로컬 대시보드로 라우팅. Qwen이 외부 웹 브라우저를 임의 선택하기 전에 우선한다.
- `JarvisLiveDashboard`: 실제 조회 성공한 자료만 표시. 에러 값은 0으로 위장하지 않고 `연결 실패/확인 불가` 표기. 새로고침 캐시를 사용하지 않고 **패널 표시 중 약 7초 간격으로 재조회**. 패널 숨김/전체 화면 Esc에서는 주기 갱신 취소.
- SwiftUI에 한 번에 하나의 패널만 표시. 금빛 코어와 독립 입력/음성/보관함 기능을 유지. 프로젝트 완료 비율, 할 일 수, 자료 분류/최근 보관 기록, DB 및 Ollama 연결을 각기 다른 구조로 표시.
- 연결되지 않은 YouTube, 주식/뉴스, 외부 서비스의 '실시간 대시보드'는 실제 데이터가 없다고 안내. 예시 숫자, 가짜 출처, 가상 API 반환값을 제공하지 않는다.
- **실시간 정의:** 영구 WebSocket이나 서버 푸시가 아니라 7초 주기 polling. 주기 갱신 동안의 프로젝트/보관함 외부 변경은 다음 조회 시 반영될 수 있다.
- **제한:** 모든 종류의 인터넷 질문이 아직 자동으로 맞춤형 리서치 대시보드가 되지는 않음. 검색은 기존 WebKit 창을 사용하며 외부 출처에서 데이터를 구조화하는 Research Field는 별도 구현 필요.

## 실기기 검증 · 2026-11-20

- 최초 사용자 기기 DECHIVE.local이 Offline이었으나 Remote Desktop Commander 재연결 확인 후 작업.
- 기존 앱 버전 v3.12.3, Git clean 확인하고 작업. 최종 앱 `~/Applications/JARVIS.app` v3.13.1 설치.
- Python 회귀 테스트 **182개** 통과. Swift 네이티브 빌드/Apple Development 서명 검증 통과.
- 별도 Swift 런타임 시험에서 11가지 표현의 의도 라우팅, 로컬 프로젝트 2개/작업 25개, 보관함 활성 0건, DB `ok`/프로필 8건/Ollama `0.40.16` 조회 통과.
- Swift 실제 런타임의 `refreshedAt`이 8초 뒤 증가했음을 확인하여 **반복 재조회 실제 동작** 검증. 숨김 시 반복 작업 취소도 확인.
- Mac 전체 화면에서 `프로젝트 현황 보여줘` → 오른쪽 PROJECT INTELLIGENCE 패널과 중앙 금빛 코어가 함께 표시됨. 1512pt×982pt Mac 화면(HiDPI 캡처 3024×1964px)으로 시각 확인.
- 연속 텍스트 요청 `저장한 자료 분석해 줘` → KNOWLEDGE ARCHIVE, `자비스 시스템 상태 보여줘` → SYSTEM TELEMETRY, `전체 대시보드 띄워줘` → LIVE OVERVIEW 실제 화면에서 확인.
- 기존 설치 앱과 자료는 변경 전 별도 보존: `~/Applications/JARVIS-Backups/JARVIS-before-v3130-20261120.app`, `~/Applications/JARVIS-Backups/JARVIS-before-v3131-20261120.app`.
- DB SQLite quick_check `ok`, 프로젝트 2개/작업 25개/확정 프로필 8건 유지, 키체인 재승인 팝업 없음.
- 전체 화면 `Esc`: 핫키를 보낸 직후 약 0.6초에는 창이 남아 있었으나 이후 추가 조회에서 화면 창이 0개로 종료된 것을 확인. 종료 중인 음성 응답의 타이밍은 macOS 스케줄링에 따라 변할 수 있음. 로컬 앱 프로세스는 남아 있음.

## 다음 단계

1. 웹검색 결과도 **실제 수집된 출처·발표 날짜·인용 텍스트** 기반으로 동적 Research Field에 구조화 (현재 미구현).
2. 소스 신뢰도/데이터 갱신 시각/오류를 명시해 숫자의 의미가 검증 가능하게 유지.
3. GitHub/YouTube/Notion 등 API 연결 시 읽기 권한·유료 비용·사생활·행동 승인을 분리.
