# JARVIS Core Architecture v1.0 — 2026-11-12

> 상태: 설계 기준 확정 / 로컬 첫 슬라이스 구현 / Mac 실기기 검증 대기.
> 자비스는 독립적인 개인 AI 시스템이고, GPT·Claude·Gemini·로컬 모델은 교체 가능한 외부 엔진이다.

## 1. 제품 원칙

1. **Memory First, Control Second.** 개인의 선택·목표·실패·검증 결과를 보존하되, 기억과 실행 권한은 별도로 관리한다.
2. **검증된 사실과 추론 분리.** 화면에 표시한 정보, 원격 서비스의 실제 데이터, 모델의 추정은 출처/시각/확신 수준을 구분한다.
3. **낮은 위험은 자동, 큰 영향은 승인.** 읽기·검색·임시시안·격리 실험은 정책 안에서 자율 실행 가능. 운영 배포, 삭제, 결제, 대외 발행, 권한 변경은 승인 후 실행한다.
4. **자비스의 기억·정책·작업기록은 자체 소유.** 어떤 모델을 써도 기억과 정책은 유지되고 마이그레이션 가능해야 한다.
5. **실패를 성공이라 말하지 않는다.** 수행 증거가 없다면 `실행됨`, `검증됨`, `완료`를 구분한다.
6. **예산 우선.** 기본은 로컬·무료, 구독=API 무제한 아님. 모델 호출에는 상한과 확인 단계를 둔다.
7. **안전한 시각화.** 입자 오브젝트·대시보드는 데이터와 분리된 UI로 구현하며 사용자가 시안을 만들고 비교·되돌릴 수 있어야 한다.

## 2. 논리 아키텍처

```text
Mac App (주 사용 장치)        iPhone Client (향후)
 ├─ Mic / Speaker            ├─ Voice / Notifications
 ├─ Screen / UI Tree         └─ Remote approval / Files
 ├─ Particles / Dashboard          │
 └─ Local device tool adapter      │
             │                     │
             └────────┬────────────┘
                      │ (auth, TLS, explicit scopes)
                JARVIS CORE
        ┌─────────────┼──────────────┐
    Context Engine  Memory DB     Policy Engine
       ├─LLM Router   ├─Decisions  ├─Approval
       ├─Retriever    ├─Projects   ├─Budget
       └─Planner      ├─Episodes   └─Audit
        └─────────────┼──────────────┘
                 Task Runtime
        ┌─────────────┼──────────────┐
      Scheduler     Tool Registry    Verifier
       ├─Queue      ├─Mac           ├─Evidence
       ├─Retries    ├─Web           └─Review
       └─Delivery   ├─Files/APIs
                    └─Sandbox
```

### 배치 원칙
- **Mac:** 로컬 마이크·화면, UI 구조 읽기, 사용자가 허용한 앱 조작, 로컬 화면 렌더링, 임시 캐시.
- **Cloud (나중):** Mac 전원과 무관하게 일정/웹 감시, 알림, 작업 큐/증거 관리. Mac 로컬 파일이나 화면은 Mac이 꺼져 있을 때 실시간 접근 불가능.
- **iPhone (나중):** 알림·음성·승인·파일 확인. Mac 꺼진 상태에서 보려면 사전 동기화된 파일이 있어야 함.
- **Obsidian (선택):** 사람이 읽는 검증된 노트/지식. 단독 작업 DB 아님.

## 3. 데이터 계약 — v1

`MemoryItem` = `{id, type: decision|preference|project_fact|lesson, text, source, created_at, confidence, review_state}`

`Project` = `{id, title, goal, status, next_action, blocking_issue, updated_at}`

`Task` = `{id, project_id, intent, inputs, state, approval_level, artifacts, evidence, errors, updated_at}`

`Capability` = `{id, status: disconnected|connected|tested|degraded, required_permissions, limitations, last_tested_at}`

`Approval` = `{task_id, proposed_change, scope, risk, approved_by, approved_at, expires_at}`

**현재 구현된 데이터는 `memory_items` 중 opt-in 일반 메모의 최소 부분과 익명화된 이벤트 이력뿐이다.** 프로젝트/작업/승인 구조는 아직 구현되지 않았다. 향후 마이그레이션으로 확장.

## 4. 한 번의 대화 실행 흐름

1. **입력:** 호출어 감지 → 사용자가 허용한 음성 입력/텍스트/화면 컨텍스트 수집.
2. **맥락:** 현재 활성 앱, 지시 대상, 직전 대화, 관련 프로젝트 기억 가져오기.
3. **이해:** 모델이 사용자 의도·불확실성·해야 할 일을 구분. 모호하거나 위험한 지시는 확인.
4. **계획:** 실행 도구·권한·예상비용·성공조건 확인.
5. **실행:** 읽기/격리 작업부터 수행. 변경 전 승인 필요 여부 확인.
6. **검증:** 파일 존재/HTTP 응답/화면 변화 등 독립 증거 확인.
7. **응답:** 성공·실패·미확인 구분해 짧게 말하고, 필요하면 자세한 로그 표시.
8. **기억:** 사용자 승인·프로젝트 결과처럼 유의미한 정보만 지속 보존.

## 5. 자율 행동 정책 초안

| 위험 | 예 | 기본 규칙 |
|---|---|---|
| 낮음 | 공고 검색, 문서 열람, 로컬 초안, 테스트 샌드박스 | 사전 허용 범위에서 가능, 요약/기록 |
| 중간 | 외부 API 호출, 유료 모델 반복 사용, 웹사이트 로그인 후 쓰기 | 목적·권한·비용 상한 확인 |
| 높음 | 서비스 배포, 결제, 파일 대량 삭제, 메일 발송, 글 공개 발행 | 명시적 승인 + 결과 검증 |

음성만으로 고위험 작업을 승인하지 않는다. 인증된 화면에서 승인해야 한다.

## 6. UI 분리 원칙

- **Identity Layer:** 음성에 반응하는 살아 있는 입자 원 (대체 불가한 핵심 아이덴티티).
- **Environment Layer:** 다크 네이비 / 은은한 은하빛 배경 / 최소한의 유동적인 모션.
- **Workspace Layer:** 작업 데이터, 결과, 출처, 수정 시안, 승인 및 로그.
- **Design Studio (향후):** 생성된 시안은 샌드박스 프리뷰 → 접근성/화면 크기 검사 → 승인 → 적용 → 롤백.

## 7. 구현 기준 및 순서

**S0, 현재 산출물:** Python 표준 라이브러리 로컬 API + SQLite opt-in 기억 + 브라우저 음성 API·TTS (가능 브라우저에서) + 화면 공유 로컬 미리보기 + 살아 있는 원형 UI + 사전 제작한 3개 대시보드 스타일.

**S1, 다음:** macOS 네이티브 셸 (SwiftUI), 마이크·화면 녹화 권한, Apple Speech 또는 Whisper 계열 음성 인식, ScreenCaptureKit과 Accessibility UI 트리의 명시적 접근. Mac에서 실제 장치 테스트 필수.

**S2:** LLM 라우터 + 사용자 소유 기억 DB + 시각 모델로 실제 화면 이해 (언제 모델에 전송했는지 알림).

**S3:** 검증 가능한 안전 실행 도구(파일/브라우저), 작업 추적, 승인 화면.

**S4:** 클라우드 작업 큐 및 iPhone 승인·알림·파일 전송. 장치 페어링/암호화/비용 상한 설계.

**S5:** 자율 감시·실험, 디자인 시안 생성·비교·적용.

## 8. 보안 및 개인정보 기본값

- 서버는 **127.0.0.1:8765**에서만 듣는다. 인터넷으로 공개하지 않는다.
- 일반 음성 명령은 기억 DB에 저장하지 않으며, `기억해:` 이후의 내용만 SQLite에 저장한다. 민감한 정보는 기억 요청 자체를 하지 않는 것이 좋다.
- 화면 공유는 브라우저의 사용 권한을 직접 받으며 **로컬 화면 미리보기만** 표시. 이미지 업로드/저장 없음.
- Web Speech 음성 인식의 구현은 브라우저 제공자에 따라 서버 처리 가능성이 있으므로, **완전 로컬 음성인식이라고 주장하지 않는다.**
- 원격 연결·파일 삭제·AWS 변경·배포·결제 기능은 없다.
- 애플리케이션 인증/멀티사용자, 네이티브 권한 흐름, 위협 모델은 후속 구현 전에 별도 설계 필요.

## 9. 공식 기술 자료

- ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Apple SpeechAnalyzer: https://developer.apple.com/documentation/speech/speechanalyzer
- Apple Accessibility: https://developer.apple.com/documentation/applicationservices/accessibility_api
- SwiftUI: https://developer.apple.com/xcode/swiftui/
