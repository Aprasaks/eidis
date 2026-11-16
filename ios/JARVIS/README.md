# EIDIS iPhone 0.3 — Matte Black

요청한 디자인으로 iPhone 화면의 **표시 이름을 EIDIS**로 바꾸고, 검은 배경과 무광 다크 패널로 다시 구성했습니다.

- JARVIS 응답 앞의 별/반짝이 표시 삭제, EIDIS 텍스트로 통일
- 기존 카메라·한국어 온디바이스 음성 인식·음성 합성 및 키보드 입력 기능 유지
- 현황: 날씨·일정·AI 분석·Mac 작업 기억은 **아직 연결 전**이며 가짜 수치/작업을 표시하지 않음
- EIDIS 앱 아이콘 리소스를 사용하도록 Xcode 프로젝트 연결
- 동일한 bundle ID `dev.dechive.jarvis.ios` 유지: **기존 iPhone JARVIS 앱을 삭제 없이 EIDIS로 이름 변경 업데이트**하기 위한 결정입니다. 별도의 EIDIS 앱 신규 설치로 중복시키지 않습니다.
- 소스 프로젝트/클래스 파일명에는 JARVIS 이름이 남지만 앱 화면과 홈 화면에 보이는 이름은 EIDIS입니다. Mac JARVIS 앱/서버는 변경하지 않습니다.

## 현재 검증 상태

2026-11-17, 인증된 Mac과 연결된 iPhone 13에서 다음 항목을 확인했습니다.

- Python 전체 회귀 테스트 **128개 통과**
- iPhone 13 시뮬레이터에서 EIDIS 0.3 **컴파일 → 설치 → 실행 → 실제 화면 캡처 성공**
- 실제 iPhoneOS 용 서명 빌드 성공; 코드 서명 검증 통과
- 기존 실물 iPhone 13의 `JARVIS 0.2 (build 2)`를 **삭제 없이** 같은 bundle ID로 업데이트: 설치 앱 목록에 `EIDIS 0.3 (build 3)` 표시
- 실제 iPhone에서 EIDIS 프로세스 실행 및 유지 확인
- 실물 기기에서 **새 0.3 화면의 카메라 버튼, 음성 인식 및 스피커 재검증은 아직 사용자가 직접 확인해야 함**. 기존 0.2의 실기기 입력·출력 성공이 새 버전의 검증을 대신하지 않음
- Mac JARVIS 서버와 기존 원본 작업 트리의 로컬 Xcode 개발팀 설정은 건드리지 않음. `main` 미병합

[실제 iPhone 13 시뮬레이터 화면](../screenshots/EIDIS_v03_iPhone13_simulator.png)

검증: `python3 -m unittest discover -s tests -q` 및 iOS Simulator `xcodebuild`.
