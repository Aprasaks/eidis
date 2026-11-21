# JARVIS Speech Finalization Recovery — 2026-11-21

## 보고된 실사용 문제
사용자는 전체화면 음성 대화에서 실시간 글씨가 화면에 정상적으로 표시되는데, 1.8초 자동 음성 종료 후 자비스가 '인식한 문장이 없습니다'라고 답하는 현상을 보고했다. 실기기에서 동일한 마이크 발화까지 재현해 확인한 것은 아니며, 코드에서 해당 증상이 발생할 수 있는 경로를 확인했다.

## 확인한 원인 후보
- LocalSpeechListener의 `finish()`는 `isListening`이 false면 즉시 빈 문자열을 반환했다. 이전 ASR 인식 오류로 `isListening=false` 상태가 된 뒤에는 **기존 transcript가 남아 있어도 반환하지 못했다.**
- `LocalSpeechDecision.acceptedText(transcript, failed: recognitionFailed)`는 종료 직전 오류가 발생한 경우 이미 받은 전사까지 거절했다.
- 두 경우 모두 전체화면 대화 쪽은 빈 결과를 '인식한 문장이 없습니다'라고 표시했다.

## 수정
1. `finishConsumed`를 음성 세션별로 관리하여 finish 시도가 한 번만 실행되게 보호. sessionId/recognitionEpoch 검사와 cancel(전체화면 Esc/취소) 무효화는 유지.
2. 인식 중 오류로 이미 녹음이 멈춘 상태라도 **현재 세션의 transcript가 실제로 존재하는 경우** finalization을 시도한다. 이미 전사된 문장만 `recoverCapturedText`로 복구. 텍스트가 완전히 없을 때는 결코 가짜 문장을 만들지 않는다.
3. 정상 종료 결과와 임시 복구를 별도로 라벨링. 임시 복구는 `마지막 임시 전사(오류 후 복구)`이고 최종 인식이라고 표시하지 않는다.
4. 전체화면 컨트롤러도 `finish()`를 호출하기 직전에 **같은 음성 세션의 화면에 실제 표시됐던 전사**를 별도로 저장. 내부 반환값이 비었지만 이 문장이 있으면 임시 전사로 사용한다. token/generation 취소 검사 후에만 답변에 사용.
5. 복구 여부와 캡처 근거를 일반 화면·왼쪽 작업 대화 패널에 표시.
6. 전사 텍스트가 이미 보이면 finalization 대기를 최대 약 0.8초로 제한(기존 최대 1.5초). 없는 경우 기존 1.5초를 유지.

## 테스트
- macos/tests/voice/main.swift 순수 Swift 테스트: 빈문장 거부, 실제 캡처한 임시 전사 복구, 최종 결과로 허위 승격하지 않기, 다중 발화 세그먼트 유지.
- tests/test_voice_finalization_recovery_v1.py 코드 계약: 세션 중복 종료 방지, 동시 취소, 화면 캐시와 listener 현재 전사만 이용, 근거 표시.
- 전체 Swift 앱 및 Python 회귀 테스트 실행 후 설치 예정.
- **사용자의 실제 마이크 말하기/ASR 오류 재현은 아직 미확인**, 그 결과는 사용자 시험으로 확인 필요.

## 복원
- 기존 Mac 개인 DB 변경 전 백업: `~/.jarvis-lab/backups/pre-voice-finalization-fix-20261121.sqlite3`.
- 앱 교체 시 기존 서명된 앱도 별도 백업. 프로젝트/기억/로그인 자료/API 토큰/코어 영상 변경 없음.
