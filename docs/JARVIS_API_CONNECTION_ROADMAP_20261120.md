# JARVIS API 연결 로드맵 — 2026-11-20

## 기본 목표

사용자가 `자비스, 전체 대시보드 열어`라고 말하면 금빛 코어 옆에 **실제 출처/조회 시각/연결 상태**를 가진 데이터만 표시한다. `유튜브 분석해줘`, `깃허브 전부 보여줘`, `자료 노션에 정리해`, `오늘 일정 보여줘`, `사진 정리해`는 서로 다른 커넥터와 권한을 사용한다. 현재 사용 중인 앱 버전: 3.14.3.

## 현재 코드로 검증된 연결

- **로컬 완료:** Qwen3.5:9B / Ollama, Python JARVIS 서버(127.0.0.1:8765), SQLite 개인 기억과 작업/자료 원장, 로컬 Git 작업복사본 읽기, 현재 금빛 코어 UI.
- **구현됨 / 현 시점 인증 상태 별도 확인 필요:** ElevenLabs 음성 합성·음성 목록(Apple Keychain), 공개 GitHub 특정 프로젝트 읽기.
- **아직 JARVIS 직접 미구현:** 인증된 GitHub 전체 계정, YouTube Data / Analytics, Google Workspace/GA4/GSC, Notion, Meta SNS, NAVER API HUB, 외부 검색 API, 날씨 등.

## 권장 순서 및 계정 준비물

| 순위 | 커넥터 | 목적 및 읽기 시작 | 준비물 / 인증 | 비고 |
|---|---|---|---|---|
| 1 | GitHub REST / GraphQL | 모든 접근 허용 저장소, Issue/PR/Actions/릴리즈 | GitHub fine-grained PAT 또는 GitHub App, 저장소별 최소 읽기 권한 | 로컬 Git 스캔과 별개; 공개 GitHub 조회는 이미 있음 |
| 1 | YouTube Data API v3 | 내 채널/영상/재생목록/댓글/공개 메타데이터 | Google Cloud 프로젝트, YouTube Data API v3, Google OAuth Desktop client | 공개 자료 일부는 API key, 내 계정은 OAuth |
| 1 | YouTube Analytics API | 내 채널의 기간별 조회수/시청 시간/유입/영상 성과 | 같은 Google Cloud 프로젝트, Analytics API, OAuth `yt-analytics.readonly` | `YouTube Reporting API`는 대량 집계 필요할 때만 |
| 1 | Google Search Console API | 데카이브/위키 노출·클릭·검색어·페이지 | Google OAuth, 사이트 속성 URL 및 접근권 | API의 최대 행 수 등 유의 |
| 1 | GA4 Data API | 사이트 트래픽·페이지·전환·이벤트 | GA4 property ID, 조회 권한, OAuth 또는 서비스 계정 | GSC와 별도 지표 |
| 2 | Brave Search API 또는 동급 검색 | 인터넷 조사 → 실제 출처 Research Field | API 등록/키; 비용 상한·쿼터 설정 | 무료 독립 요금제가 아닌 월 크레딧 형태. 읽기만 |
| 2 | NAVER API HUB | 국내 웹/블로그/뉴스 검색, 검색어 트렌드 | Naver Cloud Platform, API HUB Client ID/Key | 구 개발자센터에서 2026-07 이후 신규 신청 불가 |
| 2 | Notion API | 페이지·데이터베이스 읽기, 정리·작성 | Notion internal integration 또는 OAuth, 공유할 페이지 승인 | 쓰기는 초기에 비활성화 |
| 2 | Google Drive / Docs / Sheets API | 문서/시트/원고 검색 및 요약 | Google OAuth, 최소 범위 `drive.file` 우선 | 전체 파일 읽기는 확대 권한 필요 |
| 2 | Google Calendar API 또는 Mac EventKit | 오늘 일정·회의·알림 | Google OAuth `calendar.events.readonly` 또는 Mac 권한 | 로컬 일정은 EventKit으로 API key 없이도 가능 |
| 2 | Gmail API | 받은 편지 분석·필요한 메일 검색 | Google OAuth 및 제한 범위 (Gmail read scope는 restricted) | 추후 필요해질 때 별도 검토 |
| 2 | Discord Webhook | 조사 결과·오류·완료 알림 | 채널 웹훅 URL | 비밀정보로 취급, 채팅이나 Git에 넣지 않음 |
| 3 | Meta Graph API | Facebook Page/Instagram Professional 통계 | Meta developer app, 액세스 토큰, Page/Professional 계정 권한 | 게시물/인사이트 권한 분리 |
| 3 | Threads API | Threads 게시물/성과 | Meta app, Threads OAuth 및 적합한 권한 | 앱 심사·권한·지원 지표 확인 필요 |
| 3 | X API | X 게시물/계정 분석 | Developer account, OAuth, 사용량 기반 비용 통제 | 비용 대비 효용 확인 후 진행 |
| 3 | Google Photos Picker / Apple PhotoKit | 사진 선택·분류 및 정리 | Mac 사진 권한 또는 Google Photos Picker OAuth | Google Photos 전체 라이브러리 API는 2025년부터 제한됨 |
| 3 | Open-Meteo / 기상청 | 현재/예보 날씨 | 비상업 Open-Meteo는 key 불필요, KMA는 서비스키/신청 | 데이터 시각/지역/원천 출처 명시 |
| 3 | AWS CloudWatch / Vercel / Supabase | 인프라/배포/오류 대시보드 | 해당 계정의 읽기 권한 최소 인증, 프로젝트 ID | 운영 서비스가 확정된 것부터 |
| 선택 | 로컬 Obsidian Vault | .md 자료 검색/정리 | Mac 파일 접근 권한과 정확한 경로 | Obsidian API 없어도 로컬 폴더 읽기 가능 |
| 선택 | Kakao 메시지 | 나에게 알림 메시지 | Kakao Developers OAuth와 메시지 권한 | Discord보다 필요할 때 선택 |

## 연결·보안 설계

1. 단계별로 `provider`, `connection_status`, `granted_scopes`, `last_sync`, `next_refresh`, `rate_limit`, `last_error`, `source_url`만 관제실에 표시한다. **토큰·클라이언트 시크릿은 데이터베이스/화면/로그/커밋에 저장 금지.**
2. macOS 앱은 Apple Keychain에 비밀정보를 저장한다. OAuth는 Desktop 앱용 인증 코드+PKCE 흐름과 사용자 브라우저 로그인 사용. 서비스마다 token refresh와 철회 기능 제공.
3. 처음에는 읽기 전용. 문서 작성/업로드/삭제/발송/금전 사용 등은 별도 권한과 정책을 확인하고, 변경 기록과 되돌릴 수 있는 절차를 둔다.
4. 갱신주기: Git 로컬/작업 7~60초, 외부 API는 서비스별 quota-aware caching + 필요 시 수동 새로고침; 불필요한 7초마다 유튜브/Google API 반복 호출 금지.
5. 오류나 인증 누락 때는 가짜 숫자 대신 `연결 전`, `권한 없음`, `오류`, `최근 성공 조회: <시각>`을 표시. 과거 데이터는 실시간으로 표기하지 않는다.
6. 이미 ChatGPT의 연결 앱이 있더라도 JARVIS Mac 앱의 토큰으로 자동 승계하지 않는다.

## 등록 시작을 위한 사용자 확인

- GitHub: 로그인 계정과 접근할 저장소 범위(전부/선택) 승인. private repo는 명시적 읽기 권한 필요.
- Google Cloud: 프로젝트 생성/선택 → OAuth 동의 화면 → Desktop OAuth Client → YouTube Data/Analytics, Search Console, GA4, Drive/Docs/Sheets, Calendar API enable. 권한은 기능별 증분 동의.
- YouTube: 소유 채널 OAuth 승인. Analytics API는 `yt-analytics.readonly` 권한 필요.
- Sites: Search Console property URL, GA4 property ID 확인.
- Notion: 내부 integration 만들고 읽을 페이지에 연결 승인.
- Meta: 계정 유형 및 연결된 페이지/앱 심사·권한 확인.
- 결제 가능 API: Brave Search, ElevenLabs, X, 일부 인프라 등 자동 결제 상한을 명시적으로 설정.

## 현재 주의사항 (공식 자료 확인)

- YouTube Data API 기본 프로젝트 quota에 제한이 있고 일부 호출은 높은 quota 비용을 사용. Analytics API는 OAuth.
- GitHub 토큰 사용 시 rate limit 및 저장소별 권한 범위를 지킨다.
- NAVER API HUB는 2026-07-31부터 이관 API 신규 신청 창구이며 기존 개발자센터의 3개 서비스는 2027-06-30 중단 예정.
- Naver Blog 글쓰기 Open API는 **2020-05-06 종료**됨. 검색 API가 블로그 작성/통계 API를 뜻하지 않음.
- Google Photos Library API는 2025-03-31 이후 앱이 생성한 항목에 중심을 두므로 임의의 계정 전체 사진 목록을 읽는 용도로 설계하지 않음. Mac 로컬 PhotoKit은 별도 권한으로 가능.
- Open-Meteo 비상업 조건과 Brave 월 무료 크레딧(결제카드 요건 포함)을 혼동하지 않는다.

## 참고 공식 문서

- https://developers.google.com/youtube/data/getting-started
- https://developers.google.com/youtube/analytics/reference/
- https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- https://developers.google.com/analytics/devguides/reporting/data/v1/quickstart
- https://developers.google.com/webmaster-tools/v1/how-tos/search_analytics
- https://developers.google.com/workspace/calendar/api/auth
- https://developers.google.com/workspace/drive/api/guides/api-specific-auth
- https://developers.google.com/workspace/gmail/api/auth/scopes
- https://www.notion.com/help/create-integrations-with-the-notion-api
- https://developers.facebook.com/docs/insights/overview
- https://developers.naver.com/notice/article/32530
- https://developers.naver.com/notice/article/7527
- https://developers.google.com/photos/support/updates
- https://api-dashboard.search.brave.com/documentation/resources/help-feedback
- https://open-meteo.com/
- https://www.data.go.kr/data/15084084/openapi.do
