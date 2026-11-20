# JARVIS — 프로젝트·SNS 커넥터 실사 (2026-11-20)

## 원칙
- 읽기 전용 현황부터 연결하고, 발행·삭제·메일·배포 등 변경 작업은 별도 사용자 확인이 필요하다.
- 각 지표는 출처·마지막 조회 시각·조회 성공 여부·계정 범위를 함께 표시한다.
- DECHIVE.WIKI 글로벌 SNS(Instagram, Threads, Facebook)와 국내 DECHIVE SNS 계정을 절대 합산하지 않는다.
- 한 프로젝트에 여러 데이터 원천을 연결하지만 이름만 유사한 서비스 간 동일 프로젝트임을 자동 단정하지 않는다.
- 토큰·클라이언트 시크릿은 프로젝트 Git에 커밋하지 않는다.

## 이번 실기기 확인: 기존 연결
- GitHub CLI 로그인: Aprasaks. 접근 가능한 저장소 19개를 GitHub API에서 조회함. 19개가 모두 사용자 소유가 아님.
- Vercel CLI 현재 선택 범위: aprasaks-project. 프로젝트 6개.
- JARVIS Google YouTube OAuth 코드·Google Cloud 설정은 있으나, JARVIS HTTP `/api/youtube/status` 실시간 응답은 `needs_setup`이며 채널 데이터 미연결.
- Meta Instagram·Threads·Facebook: JARVIS와의 인증·통계 API 직접 연결 미구현. Meta 개발자 페이지를 Mac에서 열었으나 로그인/앱 생성 확인 전.

## 사용자 소유 GitHub(저장소 전체 이름으로 직접 확인한 12개)
- Aprasaks/Aprasaks.github.io
- Aprasaks/eidis
- Aprasaks/dechive-wiki
- Aprasaks/everyday-economy
- Aprasaks/gunsan-com
- Aprasaks/gunsan-table-tennis-association
- Aprasaks/dechive-ai-office
- Aprasaks/dechive-site
- Aprasaks/Aprasaks
- Aprasaks/doc24-sender
- Aprasaks/CodeLoungeV2
- Aprasaks/CodeLounge

## 현재 Vercel CLI 범위에서 확인된 6개
- gunsan-com
- gunsan-table-tennis-association
- dechive-naver-control
- dechive-site
- code-lounge
- code-lounge-v2

## 실측 기반 1차 매칭 후보
- dechive-site ↔ dechive-site : 동일 이름, 실제 배포 링크 확인 필요
- gunsan-com ↔ gunsan-com : 동일 이름, 실제 배포 링크 확인 필요
- gunsan-table-tennis-association ↔ gunsan-table-tennis-association : 동일 이름, 실제 배포 링크 확인 필요
- CodeLounge ↔ code-lounge : 이름 유사, 검증 전
- CodeLoungeV2 ↔ code-lounge-v2 : 이름 유사, 검증 전
- dechive-wiki : GitHub는 확인되었으나 현 Vercel 계정 범위에서 프로젝트 없음
- dechive-ai-office / everyday-economy / eidis / doc24-sender : GitHub 확인, 현재 Vercel 범위 미발견

## 연결 우선순위
1. Meta for Developers 계정/앱 등록 상태 확인
2. DECHIVE.WIKI Instagram: 계정 Professional 여부, API 사용 사례, 읽기 scopes, 실제 본인 계정 조회
3. DECHIVE.WIKI Threads: Threads API 전용 사용 사례와 접근 권한, 실제 게시물/인사이트
4. DECHIVE.WIKI Facebook: Page 소유·관리 권한, Graph API 및 인사이트
5. YouTube: 이미 만든 Google Desktop OAuth 클라이언트 파일 로컬 등록, 테스트 사용자 승인, 실제 읽기 응답 확인
6. GitHub/Vercel: 프로젝트별 매칭·배포·이슈/PR/Actions 구체 현황 검증
7. DECHIVE.WIKI Editorial Workspace: 운영 서버의 내부 상태를 읽기 전용 API로 연결. 포트 43122 로컬 UI는 관찰했으나 API 엔드포인트·인증 계약은 미확인.
8. 기타 사이트: GA4·Search Console, Supabase, 국내 SNS 등

## Meta API 검증 포인트
- Instagram API with Instagram Login은 Instagram Professional 계정을 대상으로 하고 Facebook Page는 이 로그인 방식에서 필수가 아니다.
- Instagram API with Facebook Login을 택하면 Facebook Page 연결·권한이 요구된다.
- Facebook Page의 Insights API는 별도 관리 권한 및 read_insights 등이 필요하다.
- Threads는 앱의 Access the Threads API use case가 필요하다. 다른 Meta use case들과 앱을 공유할 수 있는지는 생성 화면의 실제 옵션으로 검증한다.
- OAuth 승인과 토큰 저장은 별개로 설계하고, 계정 소유자가 직접 승인한다.
