# JARVIS v3.9.7 ElevenLabs 목소리 연결

## 구현
- 기존 API 키는 Keychain의 `dev.dechive.eidis.elevenlabs`에만 유지하며 소스코드나 UserDefaults에 저장하지 않음
- MenuBarExtra → `ElevenLabs 목소리 선택` 창을 사용자가 직접 열 수 있음
- 읽기 전용 `/v2/voices` 호출과 v2 400/404/422 시 `/v1/voices` 대체 조회
- 계정에 접근 가능한 목소리(이름, Voice ID, category, gender, 검증 언어)를 리스트에 표시
- provider preview_url 재생은 실제 음성합성 요청이 아님
- 원하는 목소리 선택은 Voice ID만 저장하며 기존 ElevenLabs 활성화 상태는 변경하지 않음
- 목록 조회가 실패해도 ElevenLabs 웹사이트에서 복사한 20자리 Voice ID를 직접 저장 가능
- `ID 접근 확인 · 음성 생성 없음`은 저장된 Voice ID에 대해 GET 확인만 진행
- 실제 음성 생성은 기존 `작업 및 설정 → 음성`에서 명시적으로 활성화해야 함 (크레딧 사용 가능)

## 실기기 확인과 남은 제약
- JARVIS v3.9.7 Mac 앱이 설치되어 기존 창 없이 실행되는 것 확인
- `ElevenLabs 목소리 선택` 창이 열리는 것 확인
- ElevenLabs 목록 조회 HTTP 400 (v2, v1 모두). 키/권한/응답 세부 원인은 미확정
- 키체인 항목 존재만 확인. Keychain 직접 조회는 사용자 승인이 필요한 상태로 별도 확인 필요
- 로컬 서버 건강 상태 HTTP 200, 프로젝트 2개 유지 (v3.9.5 확인)
- 사용자 요청 없이 유료 음성합성 생성하지 않음. 계정에서 음성을 가져오는 최종 결과는 아직 미검증

## 사용자 다음 동작
1. ElevenLabs 계정의 `My Voices`에서 마음에 드는 여성 목소리를 선택하고 Voice ID를 복사한다.
2. JARVIS 상단 메뉴 아이콘 → `ElevenLabs 목소리 선택` → `Voice ID 직접 연결`에 붙여넣고 저장한다.
3. 키체인 접근 확인이 나타나면 직접 승인한 후 `ID 접근 확인 · 음성 생성 없음`을 누른다.
4. 연결 확인 성공 시 작업 및 설정 → 음성에서 ElevenLabs를 명시적으로 켜고 유료 미리 듣기를 통해 출력 검증한다.
