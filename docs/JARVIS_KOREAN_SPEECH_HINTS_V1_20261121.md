# JARVIS — 한국어 음성 인식 1차 정확도 개선 (2026-11-21)

## 문제
음성 응답 속도와 날짜 정확도는 개선되었으나 사용자가 말한 내용을 자비스가 정확히 받아들이지 못하는 문제가 남았다. 음성 입력 실제 녹음/문장 대조 샘플이 아직 없으므로 어떤 단어가 얼마만큼 틀렸는지는 **미검증**.

## 진단에서 확인한 내용
- Mac 앱은 Apple `SFSpeechRecognizer(locale: ko-KR)`와 `requiresOnDeviceRecognition=true`, 실시간 `bestTranscription.formattedString`을 사용한다. 타사 클라우드 전사 API는 사용하지 않는다.
- Mac의 현재 기본 오디오 입력 장치가 블루투스인 상태로 확인되었다. 오디오 시스템 정보 기준 기본 입력 24,000Hz, MacBook Pro 내장 마이크는 48,000Hz로 표시되었다. 이 수치만으로 음질의 우열을 확정할 수는 없다. 사용자는 실제 장치 비교가 필요.
- 대화 자동 종료 기본값은 1.8초다. 문장 중간에 1.8초 이상 멈추면 하나의 명령이 둘로 나뉠 수 있다. 정확도가 떨어지면 기존 메뉴에서 2.8초 또는 4초로 수동 변경할 수 있다.
- 기존 인식기에 앱 고유 이름·기술 용어 힌트나 받아쓰기 작업 힌트가 없었다.
- 사용자가 한 실제 발화와 화면에 표시된 `YOU` 전사 문장을 대조하면 ASR(글씨부터 오인식)인지, 이후 의도 파서/모델(글씨는 정확하나 행동이 틀림)인지 구분할 수 있다.

## 변경
1. `JarvisSpeechVocabulary.swift`에 짧은 27개 앱 고유 표현/개발 용어를 등록한다. 자비스, 데카이브, DECHIVE, GitHub, Vercel, YouTube, ElevenLabs, Ollama, Qwen, Supabase, Blender, Codex 및 관련 명령 표현을 포함한다. 특정 사용자 이름·개인 파일명 등 개인정보는 넣지 않는다.
2. 매 음성 인식 세그먼트에서 `SFSpeechRecognitionRequest.taskHint = .dictation` 및 `contextualStrings`를 설정해 Apple의 한국어 온디바이스 인식을 보조한다. 원래 음성 인식 결과를 자동 교정/변조하지 않는다.
3. 실제 입력 장치의 `AVCaptureDevice.default(for: .audio)?.localizedName`과 `AVAudioEngine.inputNode.outputFormat.sampleRate`를 현재 사용 세션의 로컬 화면에 표시한다. 마이크 데이터, 녹음 파일, 전사 로그를 만들거나 외부로 전송하지 않는다.
4. 자동 종료 시간 1.8초, 기존 Qwen/ElevenLabs 설정, 브라우저, 프로젝트, 앱 기억/DB, 실행 권한은 이번에 변경하지 않는다.

## 구현 검증
- `macos/tests/voice/speech-vocabulary.swift`: 27개 단어가 중복 없이 짧은 단어·표현이며 총 100개 이하이고 핵심 명칭이 있는지 검증.
- `tests/test_jarvis_onsite_speech_hint_v1.py`: 온디바이스 유지, 받아쓰기 힌트, 실기기 입력 경로 표시, 음성 저장·자동 문자열 대체가 없는지 검사.
- Python 전체 회귀 277개와 Mac Swift 빌드 통과. 실제 한국어 음성 동일 문장 반복 비교는 사용자의 실기기 음성 테스트가 필요.
- Apple 공식 자료: `https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings`, `https://developer.apple.com/documentation/speech/sfspeechrecognitiontaskhint/dictation`.

## 다음 실기기 확인
1. Mac 시스템 설정 → 사운드 → 입력에서 **MacBook Pro 내장 마이크**를 선택해 테스트. 같은 말 3회.
2. Mac 화면의 'Mac 입력' 표시가 실제 선택한 장치와 부합하는지 확인. 블루투스 마이크로 바꾼 뒤 같은 말 3회.
3. '자비스, 깃허브 프로젝트 현황 알려줘', '자비스, 브라우저 열어줘', '자비스, 오늘은 무슨 요일이야'처럼 비교적 짧은 단일 의도 문장으로 텍스트 전사와 의도 처리 결과를 각각 비교.
4. 길고 천천히 말하는 질문은 음성 자동 종료 2.8초로 재시험. **마지막 단어가 잘리는 오류**와 **단어 자체가 다른 말로 인식되는 오류**를 구별.
5. 기본 Apple 인식이 반복적으로 불안정하면, 개인정보 동의/리소스 제한을 검증하고 Mac 전용 로컬 Whisper 등의 교체형 STT 엔진을 별도 제안. **현재 구현에는 포함하지 않는다.**

## 주의
- Apple의 contextualStrings는 해당 용어 인식을 *도울 수 있는 힌트*이지 정확도 보장이 아니다.
- 블루투스 오디오의 샘플레이트만으로 인식 품질이 나쁘다고 단정하지 않는다.
- 실제 사용자의 녹음·오인식 문장 샘플 없이 인식 정확도가 개선되었다고 주장하지 않는다.
