# JARVIS — DECHIVE.WIKI Instagram 연동 (2026-11-20)

## 확인한 계정·권한
- Meta 개발자 앱: DECHIVE JARVIS.
- Meta 비즈니스 포트폴리오: Dechive Wiki.
- Instagram: `@dechive.wiki`, ID `17841447171659454`. Instagram 계정과 비즈니스 포트폴리오 추가 확인.
- 사용자가 Meta Unified Login/Business Login 절차에서 액세스 토큰을 발급받아 직접 별도 저장함. 토큰 값은 JARVIS 저장소/채팅에 제공하지 않음.
- 발급 토큰은 Instagram 조회 외에 광고·게시·댓글·메시지 관리 권한을 포함할 수 있음. **이번 JARVIS 코드의 호출 범위는 GET 조회만**이며 권한 범위 축소/토큰 회전은 별도 작업.

## 앱에서 연결하는 방법
1. 최신 `~/Applications/JARVIS.app` 실행.
2. “자비스, 전체 대시보드 열어”로 관제실 표시.
3. `SOCIAL / YouTube · Instagram` 패널에서 **Meta 토큰 등록 / 교체** 클릭.
4. 새 창의 **SecureField**에 Meta에서 발급받은 토큰을 로컬로 입력하고 **계정 확인 후 저장**.
5. Mac이 고정 Graph API URL `GET https://graph.facebook.com/v27.0/17841447171659454?fields=id,username,followers_count,media_count`로 요청. 토큰은 URL에 붙이지 않고 Authorization Bearer 헤더로만 전송.
6. `id == 17841447171659454`, `username == dechive.wiki` 확인과 HTTP 200 응답에 성공해야만 토큰을 로컬 macOS Keychain (`dev.dechive.eidis.meta.instagram.wiki`)에 저장함.
7. UI에는 실제 조회에 성공한 `username`, `followers_count`, `media_count`, 확인 시각을 표시. 미제공 항목은 `API 미제공`으로 표시.
8. 화면이 열려 있는 동안 최소 300초 간격으로만 조회. 새 인증 절차/계정 추가는 하지 않는다.

## 보안 원칙
- Meta 토큰을 AI 채팅, 로그, Git, 환경변수, SQLite, UserDefaults 등에 저장하지 않음.
- Mac Keychain에서 `WhenUnlockedThisDeviceOnly` 옵션으로 저장. 로그인한 Mac 환경에서만 사용할 수 있음.
- 이 버전에 Graph POST/DELETE/PUT, 광고비 지출, 게시/삭제, 메시지 발송은 구현되어 있지 않음.
- 앱이 네트워크/API 오류를 받으면 임의 성공 데이터나 통계를 표시하지 않음.
- Keychain 잠금 또는 계정·권한·버전 차이로 조회가 실패할 수 있음. Meta 공식 API 스키마에 맞춰 추가 조정 필요.

## 검증 기록
- Swift 빌드 성공, Python 회귀 테스트 201건 통과(신규 Instagram 보안 계약 포함).
- 실제 사용자 토큰을 직접 받거나 읽지 않았으므로 **실제 Meta API 인증 성공은 아직 미검증**.
- 설정된 Instagram 계정 ID는 사용자가 Meta에서 확인한 값이며, 토큰으로 해당 계정에 접근 가능한지는 로컬 SecureField 입력 후 확인.

## 다음 단계
- 실제 프로필 조회 성공 후 미디어 목록, 인사이트 지표, Threads, Facebook Pages, 향후 광고 분석 연결을 별도 API 계약 및 권한으로 확장.
- 게시/광고 지출 등 쓰기 권한은 각각 별도 사용자 승인 및 금액·대상 제한 필수.
