# JARVIS iPhone 0.1

JARVIS는 별도 식별자를 가진 새로운 iPhone SwiftUI 앱입니다. EIDIS의 카메라 HUD 개념을 가져왔지만 앱 이름과 아이콘, 설치 식별자는 구별됩니다.

## 구현 기능
- 사용자가 명시적으로 켜는 후면 카메라와 HUD 오버레이
- 한국어 기기 내 음성 인식 및 기본 한국어 음성 응답
- 직접 문자 입력, 음성 중지
- 시뮬레이터에서는 카메라 영상 대신 HUD PREVIEW 표시
- 날씨, 일정, 영상 AI 분석, 지도, Mac 기억 동기화, 개인 AI는 미연결. 실제인 척하지 않음
- 카메라 영상과 인식 내용은 외부 서버에 전송하지 않음

## 실행
Mac에서 ios/JARVIS.xcodeproj를 Xcode로 열고 JARVIS 스킴을 선택합니다. 시뮬레이터를 선택하여 Run 하면 됩니다.

실제 iPhone에서는 Xcode → Settings → Accounts에서 개발팀 계정을 확인하고, JARVIS TARGET → Signing & Capabilities에서 본인 팀을 선택하여 Automatically manage signing을 켠 다음 연결된 iPhone을 대상으로 실행하세요. 실기기 권한 요청은 직접 승인해야 합니다.

## 직접 확인한 결과 (2026-11-16)
- 페어링된 iPhone 13의 설치 앱 전체 목록에서 EIDIS·JARVIS 이름/식별자를 찾지 못했으므로 삭제한 앱은 없음
- iPhone 17 Pro 시뮬레이터 빌드, 앱 설치, 실행과 화면 캡처 성공
- 한국어 기본 응답 Swift 테스트 및 Python 계약 검사 통과
- 실물 iPhone 서명 빌드는 실패: No Account for Team, No profiles for app bundle
- 기존 Mac JARVIS의 프로젝트 상태 및 DB 변경 없음

실물 iPhone에 설치하지 않았으며 실제 카메라·마이크·음성 출력은 아직 검증되지 않았습니다.

[실제 JARVIS 시뮬레이터 실행 화면](../screenshots/JARVIS_iPhone17Pro_simulator.png)
