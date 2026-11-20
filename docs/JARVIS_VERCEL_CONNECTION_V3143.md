# JARVIS Vercel 연결 1차 — 2026-11-20

## 범위
- Mac에 이미 로그인된 `vercel` CLI를 통해 **읽기 전용** 프로젝트 목록과 최근 배포 목록을 확인한다.
- 비밀 토큰·인증 파일은 추출하거나 JARVIS 코드·SQLite·로그에 보관하지 않는다.
- JARVIS 전체화면 관제실의 SYSTEM 패널에 Vercel 프로젝트 개수, 최근 배포 개수, READY/ERROR 개수, 일부 배포 상태를 표시한다.
- 기존 한 화면 레이아웃과 각 패널 내부 스크롤을 유지한다.

## 코드
- `macos/Sources/EidisMac/JarvisVercelRemoteScanner.swift`: 기존 인증 CLI의 `vercel project ls --format=json` 및 `vercel ls --format=json`만 호출한다. 비대화형 환경, 20초 제한, 실패시 민감한 stderr 비노출.
- `JarvisLiveDashboard.swift`: 전체 대시보드가 열려 있을 때 유틸리티 작업으로 실행하고 최소 120초 간격으로만 재조회. 닫을 때 표시용 작업을 취소.
- `JarvisCommandCenterView.swift`: 최근 상태를 출처별로 표시. 상태 `READY`는 해당 배포의 API 보고 상태일 뿐 사이트 사용자 환경에서 정상이라는 보증이 아니다.
- `tests/test_jarvis_command_center_v3140.py`: 읽기 전용 CLI 호출 계약 검사.

## 확인
- 2026-11-20 Mac에서 Vercel CLI 로그인 확인.
- 실제 CLI 결과: 현재 선택된 계정 범위에서 프로젝트 6개, 최근 배포 20개, 다음 페이지 있음.
- 새로운 Swift Scanner 독립 실행 결과: `status=verified`, `projects=6`, `recent_deployments=20`, `more_deployments=true`.
- 다른 Vercel 팀/계정의 프로젝트까지 모두 포함한다는 뜻은 아니다.
- 삭제·배포·승격·롤백은 구현하거나 호출하지 않았다.

## 다음
- 프로젝트별 프로덕션 배포/장애 판정은 정확한 프로젝트 식별자와 페이지 범위, 권한을 추가해 확장.
- Google Cloud OAuth 승인이 필요한 YouTube / GA4 / Search Console은 별도의 인증 절차로 구성.
