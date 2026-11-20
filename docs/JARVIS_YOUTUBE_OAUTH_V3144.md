# JARVIS YouTube OAuth 읽기 전용 연동 — 2026-11-20

## 실행 상태

- Google Cloud `DECHIVE-JARVIS`에 YouTube Data API v3, YouTube Analytics API를 사용 설정함(사용자 제공 Google Cloud 화면).
- 사용자는 Desktop OAuth 클라이언트를 생성했고, 다운로드 폴더에 해당 JSON 파일이 존재함을 확인함.
- Google 계정의 실제 OAuth 승인은 아직 **미완료**이며, YouTube 채널의 실제 통계 API 호출은 **미검증**임.

## 연결 방법 (JARVIS Mac)

1. JARVIS → "전체 대시보드 열어" → YouTube 패널에서 "인증 JSON 선택" 누르기.
2. 본인이 Google Cloud에서 다운로드한 `DECHIVE-JARVIS` 데스크톱 OAuth JSON 파일을 고르기.
3. 앱이 JSON의 프로젝트 ID/클라이언트 형식을 검사하여 `~/.jarvis-lab/oauth/youtube-client.json`에 파일 권한 600, 상위 폴더 700으로 저장.
4. "Google 계정 연결" 누르기 → Chrome/기본 브라우저에서 본인 Google 계정/YouTube 채널을 선택하여 **읽기 권한 두 개** 승인.
5. Google이 127.0.0.1 JARVIS 로컬 콜백으로 돌아오면, 서버가 state·PKCE를 확인한 다음 갱신 토큰을 macOS Keychain에만 저장.
6. YouTube 패널에 확인된 채널 이름, 구독자/영상 수, 최근 28일 조회수·시청 분수·구독 증가가 표시되는지 확인.

## 중요한 보안 규칙

- JSON/클라이언트 시크릿/Google 승인 코드/액세스 및 갱신 토큰을 채팅·Git·SQLite·로그에 기록하지 않는다.
- Google OAuth: system browser, authorization code + S256 PKCE + 단기 state + loopback 127.0.0.1. 로컬 `/api/youtube/connect`는 명시적 버튼 클릭으로만 요청.
- 필요한 scope: `youtube.readonly`, `yt-analytics.readonly`; 업로드/삭제/발행/수익 통계 권한은 요청하지 않는다.
- API 호출 결과는 최대 5분 캐시하고, 유효하지 않으면 오류로 표시한다. 채널이 여러 개라도 첫 연결된 계정 채널의 응답만 현재 표시하며 다중 채널 선택은 후속 과제.
- 앱은 클라이언트 JSON을 bundle에 포함하지 않는다. macOS Keychain에 refresh token을 보관한다.
- 현재 JSON 파일이 채팅에 공유됐으므로 클라이언트 시크릿 회전/클라이언트 재발급을 권장한다. 회전 후 로컬 앱에서 새 JSON을 다시 선택하면 된다.
- 외부 Testing 모드에서 필요한 테스트 사용자 추가 및 7일 토큰 만료는 Google Cloud 콘솔에서 확인해야 한다.

## 구현 파일

- `jarvis/google_youtube.py`: 로컬 OAuth PKCE 및 Keychain/YouTube API 조회
- `jarvis/server.py`: `GET /api/youtube/status`, `GET /api/youtube/summary`, OAuth callback, `POST /api/youtube/connect`
- `macos/Sources/EidisMac/JarvisLiveDashboard.swift`: 파일 선택/브라우저 승인 및 확인된 데이터 조회
- `macos/Sources/EidisMac/JarvisCommandCenterView.swift`: YouTube 패널 인증 버튼 및 실제 통계 표시
- `tests/test_youtube_google_oauth.py`: OAuth 권한·state/PKCE·보안 파일 권한·캐시 테스트

## 검증과 한계

- Swift 컴파일, Python 전체 회귀 테스트, 격리된 로컬 상태 API 응답 확인.
- Google 계정 승인이 없으므로 YouTube 채널 통계 실제 응답은 확인하지 못함.
- API 요금/할당량 및 Google 인증 정책에 따라 변경이 발생할 수 있음. 인증 오류 시 성공 수치를 꾸미지 않는다.
