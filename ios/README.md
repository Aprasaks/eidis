# EIDIS iPhone v0.1

실제 iOS SwiftUI 카메라 HUD + 한국어 음성 UI입니다. 미래 스마트 안경·개인 AI와 연결할 것을 염두에 둔 첫 번째 실험 앱입니다.

## 구현 완료

- Apple SwiftUI iOS 앱, 전용 아이콘, 투명 스타일 HUD와 스캔 프레임
- 사용자 요청과 권한 승인 후 iPhone 후면 카메라 실시간 미리보기, 시작/종료 버튼
- 음성 버튼을 누르는 동안만 한국어 기기 내 인식; 종료 시 최대 1.5초 최종 결과 대기
- 취소/오류/빈 문장 전송 방지; 최종/임시 인식 상태 구별
- 기본 질문에 대한 기기 내 규칙 기반 답변 + 한국어 TTS 재생
- 직접 입력, 음성 출력 중지, 카메라 미지원 시뮬레이터 표시

## 이번 버전에 포함하지 않은 것

영상·물체 자동 인식, 날씨와 일정 실시간 정보, 지도/ARKit 길 안내, Mac JARVIS 프로젝트 동기화, 자체 AI 모델 연결은 아직 작동하지 않습니다. 연결 전 상태를 그대로 표시합니다. 카메라 영상은 저장하거나 외부로 업로드하지 않습니다.

## Xcode 실행

Mac에서 ios/EIDIS.xcodeproj 파일을 Xcode로 엽니다. EIDIS 스킴을 고르고 iPhone 시뮬레이터에서 Run을 선택합니다. 시뮬레이터는 실제 카메라가 없어서 HUD PREVIEW가 표시됩니다. 하단 직접 입력에서 이디스, 안녕을 입력하면 응답 및 TTS를 확인할 수 있습니다.

실물 iPhone 설치는 Xcode Signing & Capabilities에서 본인 개발팀 선택과 신뢰/개발자 모드가 필요합니다. 카메라와 마이크 권한은 관련 버튼을 누를 때 요청됩니다.

## 개발 환경 사실

현재 Mac에는 Xcode 26.5와 iOS 26.5 SDK가 설치돼 있습니다. 페어링된 iPhone 13은 iOS 27.0.1이며, devicectl 조회에서 개발자 디스크 이미지 마운트 실패 경고가 확인됐습니다. 따라서 iPhone 실기기 설치와 실제 카메라/마이크 테스트는 미검증입니다. 최신 iOS를 지원하는 Xcode가 필요할 가능성이 높습니다.

## 검증

독립 순수 Swift 응답 테스트: ios/EIDISTests/main.swift
Python 계약 테스트: tests/test_eidis_ios_contract.py
iOS 프로젝트: ios/EIDIS.xcodeproj
실제 시뮬레이터 앱 화면: [실행 화면](screenshots/EIDIS_iPhone17Pro_simulator.png)

iPhone 17 Pro (iOS 26.5) 시뮬레이터에서 빌드, 설치, 앱 실행, 화면 캡처까지 확인했습니다.

## 다음 목표

동의 기반 안전한 비공개 동기화로 iPhone에서 Mac JARVIS의 검증된 작업 현황을 열람할 수 있도록 만들고, Mac 오프라인 여부와 마지막 동기화 시각을 명확히 표시합니다. 이후 별도 모듈로 개인 AI 모델 연결과 카메라 분석을 추가합니다.
