# EIDIS iPhone 0.3 — Matte Black

요청한 디자인으로 iPhone 화면의 **표시 이름을 EIDIS**로 바꾸고, 검은 배경과 무광 다크 패널로 다시 구성했습니다.

- JARVIS 응답 앞의 별/반짝이 표시 삭제, EIDIS 텍스트로 통일
- 기존 카메라·한국어 온디바이스 음성 인식·음성 합성 및 키보드 입력 기능 유지
- 현황: 날씨·일정·AI 분석·Mac 작업 기억은 **아직 연결 전**이며 가짜 수치/작업을 표시하지 않음
- EIDIS 앱 아이콘 리소스를 사용하도록 Xcode 프로젝트 연결
- 동일한 bundle ID `dev.dechive.jarvis.ios` 유지: **기존 iPhone JARVIS 앱을 삭제 없이 EIDIS로 이름 변경 업데이트**하기 위한 결정입니다. 별도의 EIDIS 앱 신규 설치로 중복시키지 않습니다.
- 소스 프로젝트/클래스 파일명에는 JARVIS 이름이 남지만 앱 화면과 홈 화면에 보이는 이름은 EIDIS입니다. Mac JARVIS 앱/서버는 변경하지 않습니다.

## 현재 검증 상태

Mac 원격 장치가 오프라인이라 코드 변경은 GitHub 브랜치에서 진행했습니다. **실제 iPhone 설치 및 새 UI 구동은 아직 검증하지 않았습니다.** GitHub CI 결과도 별도 확인해야 합니다.

Mac 연결이 돌아오면 `ios/JARVIS.xcodeproj`를 Xcode에서 열어 본인의 기존 Signing Team을 선택하고, 서명된 새 빌드로 같은 iPhone의 앱을 업데이트하십시오.

검증: `python3 -m unittest discover -s tests -q` 및 iOS Simulator `xcodebuild`.
