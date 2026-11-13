# JARVIS ElevenLabs 음성 연결 v1.7

## 사용자가 지정한 목소리
- 기본 Voice ID: `O2KReOFLpoR65nz6C9Se` (제공받은 Voice ID이며, 계정 접근 권한/목소리 품질은 아직 실제 확인 전).
- ElevenLabs 공식 Text-to-Speech `POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}`를 macOS 앱에서 직접 사용합니다.
- 한국어를 지원하는 Flash v2.5(빠름·비용 효율) 또는 Multilingual v2(안정적인 품질) 중 선택합니다.
- API 키는 이 채팅이나 GitHub 저장소에 넣지 않습니다. Mac 앱의 음성 탭에서 입력한 키는 **macOS Keychain**에만 저장됩니다. 계정 키 값은 설정 화면에서 다시 표시하지 않습니다.

## 사용 방법 (실제 API 호출 전 필수)
1. 새 JARVIS.app에서 **음성** 탭을 엽니다.
2. `ElevenLabs · 선택한 목소리` 상자에 Voice ID가 `O2KReOFLpoR65nz6C9Se`로 채워져 있는지 확인합니다.
3. ElevenLabs 계정에서 발급한 **API 키**를 **Mac 앱의 SecureField**에만 붙여넣고 **키 저장**을 클릭합니다. 채팅이나 프로젝트 기록, 터미널에 키를 적지 마세요.
4. Voice ID와 모델을 확인하고 **ElevenLabs 미리 듣기 · 크레딧 사용**을 클릭하면 음성 API를 1회 호출해 재생을 시도합니다. 이 호출부터 크레딧이 소모될 수 있습니다.
5. 목소리가 마음에 들면 **이후 자비스 답변을 ElevenLabs로 음성 생성** 토글을 켭니다. 켜는 순간부터 이후 자비스 **응답 텍스트가 외부 ElevenLabs 서비스에 전송**되고, 각 응답에 크레딧이 사용될 수 있습니다.
6. 중지하려면 토글을 끕니다. 키를 Mac에서 제거하려면 **키 삭제**를 누릅니다.

## 보안과 지출 제한
- **기본 OFF**. 키를 저장해도 자동으로 켜지지 않습니다. 미리 듣기는 명시적으로 누른 경우만 호출합니다.
- 한 앱 실행에서 유료 음성 **요청 시도 최대 5회**(미리 듣기 포함). 한 응답 **최대 600자**를 넘으면 API를 부르지 않고 macOS 기본 목소리로 읽습니다.
- 호출 실패, API 키/음성 사용 권한 오류, 잔여 요청 부족, 지나치게 긴 답변은 macOS 기본 음성으로 전환합니다. 자동 재시도하지 않습니다.
- API 키는 macOS Keychain의 기기 내 보호 항목으로 보관하며 설정/로그/로컬 웹/SQLite/앱 소스에 적지 않습니다.
- 변환된 음성 데이터는 메모리에서 재생하며 자동 파일 저장이나 공개 업로드를 하지 않습니다.
- API 요청에는 음성을 만들기 위한 **자비스 응답의 실제 텍스트**가 포함되므로 민감한 작업·기밀 답변에는 토글을 끄세요.
- API는 실제 성공하지 않아도 호출 시도에 따라 공급자 크레딧을 사용할 수 있습니다. 이번 개발·CI는 사용자의 API 키를 사용하지 않았고 유료 요청도 하지 않았습니다.

## 정확한 검증 범위
- Python 소스 계약 테스트 및 실제 Mac SwiftUI 앱 빌드로 선택/Keychain/옵트인/제한/로컬 음성 대체 코드를 확인합니다.
- **ElevenLabs API 인증, 제공 Voice ID의 계정 접근, MP3 재생 음질은 아직 실사용 검증 전**입니다. 인증과 음성 재생은 사용자가 Mac 앱에서 직접 미리 듣기를 눌러야 알 수 있습니다.
- ChatGPT Plus 및 ElevenLabs 구독은 별개의 청구·권한 구조일 수 있습니다. 연결 전 ElevenLabs 계정의 API 사용 권한과 잔여 크레딧을 확인하세요.

공식 규격: https://elevenlabs.io/docs/api-reference/text-to-speech/convert
지원 언어·모델: https://elevenlabs.io/docs/overview/capabilities/text-to-speech