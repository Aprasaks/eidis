# JARVIS Project Ledger v1.3

프로젝트 상태를 직접 기록하고, GitHub에서 확인한 사실을 별도 보관하는 첫 프로젝트 상태 시스템입니다. 대기 화면은 유지하고, 작업 공간을 열 때만 프로젝트 화면이 나타납니다.

## 실제 구현

- 프로젝트 이름, 목표, 선택적 공개 GitHub owner/repo 저장
- 작업 추가와 상태 변경: 예정(todo), 진행(doing), 막힘(blocked), 완료(done)
- SQLite 영구 저장 및 상태 변경 감사 이력: 이전 상태, 새 상태, 시각, 사용자 수동 변경이라는 출처
- 작업은 직접 바꾼 경우에만 완료 처리. GitHub 성공이 완료로 자동 전환되지 않음
- 말로 "우리 프로젝트 현황 알려줘"라고 요청하면 저장된 프로젝트 상태만 요약
- GitHub 공개 API 읽기: 저장소가 설정된 프로젝트에서 사용자가 확인 버튼을 누를 때에만 실행
- GitHub 기본 브랜치 HEAD SHA, 확인 시각 및 현재 커밋과 일치하는 일부 Actions Workflow 결과만 저장
- 이전 커밋의 성공 CI 결과를 현재 커밋 성공으로 취급하지 않음
- 비공개 저장소, Mac 앱 실기기 동작, AWS 공개 배포 상태까지 검증하는 기능은 아님

## 출처 원칙

**사용자 기록**: 프로젝트 목표, 작업 제목, 작업 상태. 이는 사용자 입력 사실이며 독립적으로 검증된 완료 결과가 아닙니다.

**GitHub 직접 확인**: 사용자의 명시적 버튼 클릭 이후 공개 GitHub REST API에서 가져온 커밋·일부 Workflow 결과. 확인 시각이 표시되며 이후 변경되었을 수도 있습니다. API 요청 실패 시 성공으로 저장하지 않습니다.

두 출처는 서로 다른 SQLite 테이블에 저장되며, GitHub 확인 결과로 사용자의 작업 상태를 자동 수정하지 않습니다.

## 보안과 비용

- 기존 localhost Host/Origin 검사 적용.
- GitHub 주소는 owner/repo 문자열만 입력 허용. 요청은 고정 HTTPS api.github.com으로만 전송하며 리다이렉트는 따라가지 않음.
- GitHub 로그인이나 액세스 토큰 필요 없음. 공개 API GET 전용.
- 외부 네트워크 호출은 사용자 검증 버튼을 누를 때만 시작하며 자동 폴링 없음.
- 유료 AI API 호출 없음, GitHub 코드 변경/배포/삭제 없음.
- 프로젝트 이름·목표·작업 제목은 로컬 SQLite에 **암호화되지 않은 텍스트**로 저장. 비밀번호나 개인 비밀을 입력하지 마세요.
- 구석 터미널에는 실행 분류만 기록. 프로젝트/작업 이름 원문은 활동 로그에 남기지 않음.

## API

GET /api/projects — 로컬 프로젝트와 작업, 마지막 GitHub 확인 결과

GET /api/projects/history?id=숫자 — 작업 상태 변경 이력

POST /api/projects — name, goal, repo

POST /api/projects/task — project_id, title

POST /api/projects/status — project_id, task_id, status

POST /api/projects/github/check — project_id; 명시적 일회성 공개 API 검증

## 검증

Python 단위 테스트는 SQLite 재시작, 소유권 확인, 상태 전환 감사 기록, GitHub API 모의 응답, GitHub 최신 커밋과 오래된 CI 불일치, 외부 Origin 차단, 로그 원문 미수집을 검사합니다.

Chromium 데스크톱 및 모바일 테스트는 실제 프로젝트 등록·작업 추가·상태 변경과 필요한 화면 전환을 검사합니다.

**현재 사용자 GitHub 연결을 자비스 독립 앱으로 넘겨주거나 실제 공개 API 인증을 수행한 것은 아닙니다.** 실기기 검증 및 실제 GitHub 네트워크 결과는 사용자가 로컬 앱을 실행하고 검증을 요청할 때 별도로 확인해야 합니다.
