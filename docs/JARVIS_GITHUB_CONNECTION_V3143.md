# JARVIS GitHub 연결 1차 — 2026-11-20

## 목적과 범위

- 전체화면 명령 관제실에 로컬 Git 작업복사본과 GitHub 로그인 계정의 원격 저장소를 분리 표시한다.
- Mac에서 기존 GitHub CLI 로그인만 재사용한다. 토큰을 추출하거나 앱·SQLite·Git·로그에 저장하지 않는다.
- 현재는 **읽기 전용 저장소 목록**이다. 이슈/PR 상세 목록과 Actions 성공·실패 분석은 후속 연결 범위다.

## 구현 파일

- `macos/Sources/EidisMac/JarvisGitHubRemoteScanner.swift`: `gh api --method GET --paginate /user/repos...` 고정 인자를 쓰는 로컬 GitHub API 리더. 기본 브랜치, 공개/비공개, 마지막 push 시각, API의 `open_issues_count`를 수집한다.
- `macos/Sources/EidisMac/JarvisLiveDashboard.swift`: 화면을 열 때 별도 유틸리티 작업에서 조회하고 60초마다 재검사한다. 대시보드 닫기 시 조회 표시 작업을 취소한다.
- `macos/Sources/EidisMac/JarvisCommandCenterView.swift`: 기존 한 화면 배치/개별 스크롤 유지. GitHub API와 로컬 Git을 한 패널 안에서 출처를 나눠 보여준다.
- `tests/test_jarvis_command_center_v3140.py`: API 읽기 전용 명령과 새 UI 계약을 검사.

## 실제 검증

- Mac `DECHIVE.local`: GitHub CLI가 기존 keyring 인증 계정 `Aprasaks`에 로그인되어 있음을 확인.
- 같은 Mac에서 GitHub REST API의 접근 가능 저장소 목록 19개 조회.
- 새로운 네이티브 Scanner의 독립 실행 테스트: `status=verified`, `remote_repository_count=19`, `truncated=false`.
- Swift 디버그 빌드, macOS Apple Development 코드 서명 및 `codesign --verify --deep --strict` 통과.
- Python 전체 테스트 189건 통과.
- 사용자 화면에서 JARVIS 전체 대시보드에 실제 표시되는지 여부는 재시작 후 UI 확인이 필요하다.

## 한계 및 보안

- REST `open_issues_count`에는 Pull Request도 포함된다. 이슈와 PR을 따로 센 수치가 아니다.
- 원격 계정에서 조회 가능한 저장소가 100개를 초과하면 화면에는 최근 push 기준 100개만 보여주고 `전체 목록 아님`을 표시한다.
- `gh`가 설치되지 않았거나 로그인/네트워크 문제가 있으면 숫자를 꾸미지 않고 오류를 표시한다.
- 토큰 권한 범위가 광범위할 수 있으므로 장기적으로는 JARVIS 전용 Fine-grained PAT / GitHub App의 **최소 읽기 권한**으로 격리한다.
- 화면의 다른 로컬 데이터는 약 7초 간격이지만 GitHub 원격 API는 비용·할당량과 부하 때문에 최소 60초 캐시 간격으로 조회한다.
- 사용자 계정의 이슈/PR/Actions 세부현황, 전체 조직 범위 확인은 2차 연동에서 추가해야 한다.
