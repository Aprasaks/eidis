# JARVIS 파일 정리 및 Git 보존 기록 · 2026-11-24

> 이 문서는 실제 macOS 기기에서 확인한 정리 내역이다. 현재 앱의 내부 자료·기억·일정·알람을 삭제하지 않았다.

## 남겨둔 현재 실행본

- Mac 실행 앱: `~/Applications/JARVIS.app` — v3.14.13 (build 87). 정리 전후 앱 파일 존재, 실제 프로세스 확인.
- iPhone 실행 앱: `dev.dechive.jarvis.mobile` — v0.4.1 (build 10). 설치 상태 확인.
- 현재 개발 소스: `~/Documents/JARVIS-FULLSCREEN-PREVIEW`, Git 브랜치 `work/jarvis-fullscreen-overlay`.
- Git 공통 저장소가 `~/Documents/JARVIS/.git`에 있어 이 디렉터리는 삭제하지 않는다.
- Mac 기억: `~/.jarvis-lab/memory.sqlite3` 및 그 WAL, 사용자 설정·자료·프로젝트·뉴스 기록 전체 보존.
- iPhone 알람·캘린더 앱 데이터와 `~/Library/Application Support/JARVIS/Backups/` 백업 파일 보존.
- 마지막 구형 롤백 앱 `~/Applications/JARVIS-Backups/JARVIS-v3.14.12-20261124-023842.app` 한 개 보존.

## Git 보존

1. 현재 최신 소스 변경 파일 122개를 `a10635993d59`에 커밋하고 `origin/work/jarvis-fullscreen-overlay`로 푸시. 원격 해시 동일함을 확인함.
2. 과거 v3.8 Blender 코어의 미커밋 원본 및 구현 시도를 `01dce8fc7307`에 커밋하고 `origin/work/jarvis-immersive-home-v38`로 푸시. 원격 해시 확인함.
3. 오래된 iPhone 작업 트리의 자동 포맷 및 개인 서명 팀 설정 차이는 **GitHub에 올리지 않고**, 로컬 비공개 `Application Support/JARVIS/Backups/`에 패치로 백업 후 구형 작업 트리 변경을 원복했다.
4. 다른 과거 브랜치들은 Git 공통 저장소의 브랜치 참조로 보존한다. 물리적인 작업 트리만 제거했다.

## 실제 삭제한 항목

### 이전 macOS 테스트·백업 앱 (현재 설치 앱은 건드리지 않음)

- `~/Applications/JARVIS Fullscreen Preview.app`
- `~/Applications/JARVIS FullHD Test.app`
- `~/Applications/JARVIS-v36-staged-invalid-signature-20261117.app`
- `~/Applications/JARVIS-Backups/JARVIS-legacy-2026-11-13.app`
- `~/Applications/JARVIS-Backups/JARVIS-v3.14.10-20261124-015122.app`
- `~/Applications/JARVIS-Backups/JARVIS-v3.14.11-20261124-015835.app`

### 예전 Git 작업 트리 (Git 브랜치 내용은 보존됨)

- `~/Documents/JARVIS-MAC-v35`
- `~/Documents/JARVIS-MAC-v36`
- `~/Documents/JARVIS-MAC-v37`
- `~/Documents/JARVIS-MAC-v38`
- `~/Documents/JARVIS-EIDIS-v03`
- `~/Documents/JARVIS-EIDIS-v04`

### 재생성 가능한 현재 프로젝트 빌드 산출물

- `~/Documents/JARVIS-FULLSCREEN-PREVIEW/dist`
- `~/Documents/JARVIS-FULLSCREEN-PREVIEW/macos/.build`

총 약 **1.3GB 규모**의 기존 디스크 사용량을 정리했다. 추정치는 삭제 전 `du -sh` 합계로, 실제 APFS 여유 공간 변화와 차이가 날 수 있다.

## 의도적으로 삭제하지 않은 항목

- `~/Documents/JARVIS`: 다른 Git 작업 트리의 공통 Git 데이터와 브랜치 참조를 가진 원본 워크트리.
- `~/Desktop/eidis-validation`과 연결된 `eidis-voice-preview`, `eidis-diagnostics-preview`, `eidis-elevenlabs-preview`: 현재 저장소에서 확인되지 않는 **별도 고유 Git 커밋 이력**을 보유한 과거 저장소. 현재 앱과 직접 연결되지 않지만 그 고유 이력의 안전한 복구 경로가 확보되기 전까지는 보존.
- `~/.jarvis-lab`, `~/Library/Application Support/JARVIS`, Mac/iPhone 사용자 데이터: 기존 기능 및 사용자 설정에 필요할 수 있는 데이터.
- Docker/Postgres: JARVIS 외 프로젝트와 연관된 별도 설치물이며 이번 정리 범위에서 제외.

## 검증

- 정리 전 Python 회귀 테스트 **357개 통과**.
- 정리 전 최신 Mac Swift 빌드 **성공**.
- 구형 v3.8 작업 트리에서도 Swift 빌드 성공.
- 최신 Mac 실행 앱 유지, 원본 데이터 파일 유지, 현재 Git 작업 트리 clean 확인.
- 삭제한 `.build`와 `dist`는 소스에서 재생성되는 산출물이므로 다음 빌드 때 다시 생성된다.

**주의:** 이 정리는 설치 앱·기억 데이터를 마이그레이션하거나 현재 앱을 새로 빌드·설치한 작업이 아니다. 나중에 `main` 병합이 필요하다면 코드 변경 및 테스트를 별도로 검토한다.
