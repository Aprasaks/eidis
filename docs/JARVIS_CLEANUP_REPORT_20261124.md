# JARVIS 개발 파일 통합·정리 최종 기록 · 2026-11-24

> 사용자 요청: **현재 실제로 사용하는 JARVIS와 필요한 데이터만 남기고, 구형 JARVIS/EIDIS 테스트 폴더는 모두 정리한다. GitHub에는 최신 소스를 유지한다.**

## 최종 유지 대상

- **현재 Mac 앱**: `~/Applications/JARVIS.app` — v3.14.13 / build 87.
- **현재 iPhone 앱**: `dev.dechive.jarvis.mobile` — v0.4.1 / build 10.
- **유일한 현재 JARVIS 개발 소스**: `~/Documents/JARVIS-FULLSCREEN-PREVIEW`.
- 개발 폴더에는 이제 **독립된 `.git/` 디렉터리**가 있으며, 더 이상 구형 `~/Documents/JARVIS/.git`에 의존하지 않는다.
- GitHub 원격 저장소: `https://github.com/Aprasaks/eidis.git`.
- **GitHub `main` 브랜치**와 `work/jarvis-fullscreen-overlay`에 모두 최신 통합 소스 `289af75eb26b22f02cfb9b8b9624e5a50a7a8df2`가 반영됐음을 확인했다(이 보고서를 작성하기 전 기준).
- **로컬 음성 실행 환경**: `~/Documents/JARVIS-VOICE-LOCAL`. 현재 `JarvisVoiceSetupView.swift`가 실제로 참조하므로 삭제하지 않는다.
- **기억·프로필·캘린더 등 실제 사용자 데이터**: `~/.jarvis-lab/`의 SQLite 및 데이터. 삭제하지 않는다.
- **설정과 안전한 복구 기록**: `~/Library/Application Support/JARVIS/`. 삭제하지 않는다.
- `tools/chrome-bridge/node_modules`는 현행 Chrome 연결 기능에 필요할 수 있으므로 현행 소스 아래 보존한다.
- 앱의 서명·인증·보안 설정과 키체인, iPhone 앱 데이터도 변경하지 않았다.

## Git 보존과 통합 절차

1. 현행 소스의 미커밋 수정과 iPhone JARVIS를 `a106359`에 커밋하고 작업 브랜치에 푸시.
2. 구형 v3.8의 Blender/3D 모델과 코드 중 미커밋 원본을 `01dce8fc7307`에 커밋하고 `work/jarvis-immersive-home-v38` 원격 브랜치에 푸시.
3. 1차 구형 파일 정리 기록을 `289af75`에 커밋·푸시.
4. GitHub `main`을 `289af75`로 **강제 푸시 없이 fast-forward 업데이트**. 작업 브랜치와 `main`의 해시가 같은 것을 검증.
5. 완전한 과거 JARVIS Git 이력과 독립된 바탕화면 EIDIS Git 이력을 각각 `git bundle --all`로 로컬 백업하고 `git bundle verify` 확인:
   - `~/Library/Application Support/JARVIS/Backups/JARVIS-ALL-GIT-HISTORY-before-consolidation-20261124-0405.bundle`
   - `~/Library/Application Support/JARVIS/Backups/EIDIS-old-desktop-unique-git-history-20261124-0405.bundle`
6. 최신 브랜치를 `--no-hardlinks`로 독립 복제하고 동일 트리 해시/파일 수/원격 상태 확인. 현재 소스 경로로 이동한 뒤 `main`을 추적하도록 설정. `.git/objects/info/alternates` 없음.
7. 이 새로운 독립 소스에서 **Python 회귀 357개 통과, Mac Swift 빌드 성공, iPhone 시뮬레이터 Xcode 빌드 성공**. 그제야 구형 Git 본체를 제거했다.

## 실제 제거한 구형 앱·소스·실험 폴더

### ~/Applications

- `JARVIS Fullscreen Preview.app`
- `JARVIS FullHD Test.app`
- `JARVIS-v36-staged-invalid-signature-20261117.app`
- `JARVIS-Backups/JARVIS-legacy-2026-11-13.app`
- `JARVIS-Backups/JARVIS-v3.14.10-20261124-015122.app`
- `JARVIS-Backups/JARVIS-v3.14.11-20261124-015835.app`
- `JARVIS-Backups/JARVIS-v3.14.12-20261124-023842.app`
- `~/Applications/JARVIS-Backups` 디렉터리 자체도 제거함.

### ~/Documents

- 이전 Git 공통 저장소를 담은 `JARVIS` 구형 프로젝트 **전체 제거**.
- `JARVIS-MAC-v35`, `JARVIS-MAC-v36`, `JARVIS-MAC-v37`, `JARVIS-MAC-v38`.
- `JARVIS-EIDIS-v03`, `JARVIS-EIDIS-v04`.
- 중간 이전 작업 트리 `.JARVIS-OLD-LINKED-WORKTREE-20261124`.
- 변환 작업에 사용한 일시 staging 폴더는 최종 현재 소스 경로로 이동했으며 남아 있지 않음.

### ~/Desktop

- `eidis-validation`.
- `eidis-voice-preview`.
- `eidis-diagnostics-preview`.
- `eidis-elevenlabs-preview`.
- 위 네 폴더의 고유 코드 이력은 해당 `git bundle`에 보존했다.

### 빌드 캐시·휴지통

- 현재 프로젝트의 재생성 가능한 `dist/` 및 `macos/.build/` 제거(최종 빌드 검증 후에도 캐시 재삭제).
- 기존 휴지통의 구형 `dechive-jarvis` 로그 폴더 2개 제거.
- Python 캐시 등 자동 생성 부산물은 애플리케이션 작동에 영향 없도록 필요할 때 개별 정리 가능.

## 최종 확인

- `~/Documents`에서 이름에 JARVIS/EIDIS가 들어가는 유지 폴더는 현행 **`JARVIS-FULLSCREEN-PREVIEW`** 및 현행 음성 의존성 **`JARVIS-VOICE-LOCAL`**이다.
- `~/Desktop`에는 위의 구형 EIDIS/JARVIS 실험 폴더가 남아 있지 않다.
- `~/Applications`에는 현재 `JARVIS.app`만 남긴다.
- 로컬 Git `main`은 `origin/main`을 추적하며 작업 트리는 clean이다(이 문서 자체 커밋 전 기준).
- 기억 DB는 다른 소스 디렉터리에 있으므로 정리 대상에서 제외. 다른 프로젝트의 Docker/PostgreSQL도 건드리지 않았다.

## 유지 원칙

새 기능은 `~/Documents/JARVIS-FULLSCREEN-PREVIEW` 한 곳에서 개발하고, 원격 `main`에 테스트 완료된 최신 상태를 푸시한다. 단, 앱으로 설치하는 것은 별도 빌드/설치 검증이 필요하며, Git 푸시만으로 Mac/iPhone에 자동 배포됐다고 주장하지 않는다. 사용자 데이터 파일은 GitHub에 올리지 않는다.
