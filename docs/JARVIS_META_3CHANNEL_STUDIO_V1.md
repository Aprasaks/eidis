# DECHIVE.WIKI META 3채널 연결·콘텐츠 작업실 V1
작업 대상은 **DECHIVE.WIKI 계정의 Facebook Page, Instagram, Threads**다. 개인/국내 DECHIVE SNS와 혼용하지 않는다.

## 공식 인증 흐름·기능 범위 (2026-11-22)
- Facebook Page: Facebook Graph v27.0, Page Access Token. 숫자 Page ID와 토큰을 사용자 본인이 앱에서 입력해야 함. GET /me?fields=id,name,username 결과가 그 Page ID와 DECHIVE WIKI 이름/사용자명에 일치할 때만 저장. 관리용 Page 토큰과 일반 User Token을 혼동하지 말 것. 조회 권한 외 실제 게시에는 pages_manage_posts, pages_read_engagement 등 별도 권한 확인 필요.
- Instagram: 원래 Facebook Business Graph 방식(`graph.facebook.com/v27.0/<PINNED_IG_ID>`)과 별개인 Instagram Login 방식(`graph.instagram.com/v27.0/me`)을 명시적으로 선택 가능. 기본은 기존 저장된 Facebook Business 모드. `@dechive.wiki` 확인 후에만 Keychain 저장. Instagram Login에는 instagram_business_basic, 게시 시 instagram_business_content_publishing 등이 필요. 기존 HTTP 400 토큰은 검증 성공으로 취급하지 않음.
- Threads: 공식 `graph.threads.net/v1.0/me?fields=id,username`에 Threads User Token 사용. `@dechive.wiki`가 정확히 일치할 때만 Keychain 저장. 기본 조회 threads_basic, 발행 threads_content_publish 등 필요.
- 서로 다른 채널의 토큰을 공유하거나 사용자 몰래 다른 계정으로 대신 연결하지 않는다. Meta Developer 앱/Business Portfolio의 실제 권한과 관리자 동의/인증이 있어야 세 채널을 모두 연결할 수 있다.
- 키체인에 토큰만 저장하며 로그·SQLite·JSON·Git·AI 프롬프트로는 보내지 않는다. Facebook ID 및 선택된 Instagram 로그인 방식만 UserDefaults에 저장하며 비밀값이 아니다.
- 기존 Instagram 계정 토큰은 저장돼 있지만 HTTP 400으로 API 인증 실패. Facebook/Threads는 실제 인증 토큰 미등록 상태. **세 채널 연동 완료라고 주장하지 않는다.**

## 자동 콘텐츠 제작 — 현재 실행 가능한 범위
- META 카드의 `AI 콘텐츠·광고 초안 작업실`에서 원클릭으로 `dechive.wiki` 홈페이지에 노출된 Knowledge 원문 중 하루 단위로 순환 선택한 공개 글을 읽는다. 이 목록은 **최신 글 목록이라고 보장하지 않는다**.
- 로컬 Ollama `qwen3.5:9b-q4_K_M`로 Facebook 글·Instagram 캡션·Threads 글·광고 콘셉트 각 1개 생성. 학습/검증 근거로 실제 Wiki 원문 URL을 코드로 붙이고, 짧거나 임의 계정 URL을 생성하면 저장 거부. 모델의 문장 단위 사실 검증은 인간이 추가로 수행해야 한다.
- 공개 원문만 이용. 생성 결과는 Mac Application Support `DECHIVE-JARVIS/meta-social-draft-v1.json`에 로컬 저장. 편집·복사·검토 완료 표시 지원. Threads 500자 기준 초과 시 경고.
- 광고 콘셉트는 소재/대상/실험 질문 제안일 뿐이다. 예산, 광고 계정, 크리에이티브, 성과는 설정하거나 생성했다고 주장하지 않는다.
- 실제 API 발행, 예약 게시, 광고 집행, 결제, 광고 계정 쓰기, 자동 승인 **미구현 / 미실행**. 이후 자산 및 권한 검증, 지출 상한, 계정/캠페인 단위 승인 뒤에만 별도 구현.
- 현재 사용자 동의/실제 인증·정책 확인 전에는 완전 자동 게시·광고 지출 불가.

## 공식 참조
- https://developers.facebook.com/docs/instagram/platform/instagram-api/changelog/
- https://developers.facebook.com/docs/graph-api/reference/user/accounts/
- https://developers.facebook.com/docs/graph-api/reference/page/feed/
- https://www.postman.com/meta/threads/documentation/dht3nzz/threads-api

## 검증
- Mac Swift 실제 빌드, Python 소스 회귀 테스트, UI 스크린샷. 별도 로컬 Qwen smoke에서 Mount Vesuvius 원문을 근거로 Facebook/Instagram/Threads/광고 초안 총 4개 생성. 초기 출력이 무관한 개인 계정 URL이어서 폐기하고 길이·링크 검사 후 재실행하여 4개 초안과 Wiki 원문 링크 포함 검증.
- 인증 가능한 Page ID 및 Threads 토큰을 본인이 연결하기 전까지 실 API 연결 성공은 미검증.
