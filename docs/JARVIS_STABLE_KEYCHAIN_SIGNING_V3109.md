# JARVIS v3.10.9 — macOS ElevenLabs 키체인 반복 허용 팝업 수정

## 실기기에서 확인한 근본 원인

- 기존 패키징 `macos/scripts/package-app.sh`의 `/usr/bin/codesign --force --sign - "$APP"`는 **ad-hoc 서명**이었다.
- 실제 설치된 v3.10.8의 지정 요구사항은 `cdhash H"..."` 형태였고, 코드/리소스가 업데이트될 때마다 cdhash가 바뀌었다. 이는 기존 키체인 항목 `dev.dechive.eidis.elevenlabs`에 대한 `항상 허용` 기록이 새 빌드에 재사용되지 않는 원인이다.
- 현재 Mac의 `security find-identity -v -p codesigning`에서 Apple Development 인증서 1개가 유효했고, 인증서 만료일은 2027-06-14(UTC)였다.

## 수정 사항

- 패키징은 `Apple Development`의 유효한 코드 서명 신원 하나를 자동 선택하거나, 여러 개인 경우 `JARVIS_SIGNING_IDENTITY` 환경 변수로 명시적으로 지정한다.
- 유효한 서명 신원이 없거나 여러 개인 경우 **빌드 실패**. ad-hoc 서명으로 조용히 되돌리지 않는다.
- `codesign --verify --deep --strict`와 Apple anchor 기반 designated requirement 검증을 수행한다.
- API 키 저장/읽기 로직은 변경하지 않았다. 키는 기존 Mac 로그인 키체인에 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`로 보관된다. 파일·UserDefaults·Git에 저장하거나 출력하지 않는다.

## 검증 (2026-11-20)

- `~/Applications/JARVIS.app` v3.10.9 설치, 코드 서명 검증.
- 계약 테스트 161개 통과, Swift 빌드 및 앱 패키징 통과.
- **서로 다른 코드 서명 해시**를 가진 두 앱을 동일한 Apple Development 인증서로 서명하고 designated requirement가 동일한지 검증: 통과.
- 지정 요구사항에 `identifier "dev.dechive.eidis"`와 `anchor apple generic` 및 개발자 인증서가 포함됨을 확인.
- 기존 JARVIS v3.10.8 백업은 `~/Applications/JARVIS-Backups/JARVIS-before-v3109-stable-sign-20261120.app`에 별도로 보존.
- 설치 후 JARVIS 프로세스 실행, 프로젝트 로컬 서버 SQLite 상태 `ok`, Ollama 응답 정상.
- macOS SecurityAgent에서 **기존 키체인에 대한 신규 서명 최초 승인 팝업이 한 번 나타난 상태**를 확인. 사용자가 Mac 로그인 암호를 직접 입력하고 `항상 허용`을 택해야 함. 해당 사용자 동작은 자동화하지 않음.

## 사용자 확인 필요

1. macOS 키체인 팝업에서 직접 로그인 암호 입력 후 `항상 허용` 클릭 (암호는 ChatGPT에 전달하지 말 것).
2. JARVIS 종료·재실행 및 음성 명령 시 팝업이 반복되지 않는지 확인.
3. 다음 앱 배포에도 같은 Apple Development 서명 신원을 사용해야 함. 인증서 교체/팀 변경/만료 또는 키체인 ACL 초기화가 있으면 다시 한 번 승인할 수 있다.

## 주의

- `security set-key-partition-list`로 모든 앱에 접근을 허용하거나 키체인 보안을 낮추지 않았다.
- `security find-generic-password`로 서비스 항목 메타데이터 존재만 확인했고 API 키 값 자체를 읽거나 출력하지 않았다.
- 인증서가 없는 다른 Mac에서는 정상적으로 빌드를 중단한다. 해당 Mac의 유효한 서명 신원을 마련해 명시적으로 선택한다.
