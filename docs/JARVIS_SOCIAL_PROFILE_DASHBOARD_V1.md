# JARVIS — 실제 채널 프로필 대시보드 (2026-11-22)

## 목적

전체 관제실 왼쪽에서 DECHIVE.WIKI Instagram·Facebook·Threads와 DECHIVE YouTube의 **실제 프로필 사진과 확인 가능한 지표**만 간결하게 보여준다. 중앙 금빛 코어는 원본 루핑 영상 그대로 유지한다.

## 구현

- Instagram: 기존 Keychain 토큰으로 실제 계정 ID와 사용자 이름 검증 후, Meta API의 `profile_picture_url`, `followers_count`, `media_count`를 별도 선택 조회. 미지원 필드는 `—`.
- Facebook: 인증된 Dechive WIKI Page 토큰 검증 후 `picture`, `followers_count`(또는 `fan_count`)를 별도 선택 조회. 게시물 수를 근거 없이 만들지 않음.
- Threads: 인증된 @dechive.wiki 계정의 `threads_profile_picture_url`을 별도 선택 조회. 팔로워/게시물 수가 없는 경우 `—`.
- YouTube: 기존 실제 `channels.list(mine=true,part=snippet,statistics)` 요약에 `snippet.thumbnails`의 HTTPS 이미지 URL을 전달하고 구독자·영상·조회수를 간결히 표시.
- 계정 카드 클릭 또는 “인스타 열어봐”, “스레드 열어봐”, “페이스북 열어봐”, “유튜브 열어봐” 명령 시 자비스의 기존 임시 WKWebView에 고정 공식 프로필 URL을 연다. 유튜브 주소는 조회한 채널 ID를 사용하며, ID가 검증되지 않은 경우 열지 않는다.
- 사이트가 Instagram/Meta 로그인을 요구할 수 있음. 앱 내부 WKWebView는 Chrome 로그인 세션을 자동으로 가져오지 않음. 자동 로그인·게시·광고 집행 기능은 없음.
- SNS 프로필을 닫으면 통합 대시보드로 복귀. 기존 음성/대화창·시스템 카드·코어는 그대로.
- API 프로필 상세 조회 실패는 연결 검증 실패로 오인하지 않음. 토큰을 URL·파일·로그에 기록하지 않음.

## 실제 확인

- Swift macOS 빌드 및 Apple Development 코드 서명, 설치본 해시 비교 통과.
- Python unit tests 322건 통과. Swift 프로필 명령 8/8 및 YouTube URL 검증 테스트 통과.
- 실제 Mac 2560×1080 관제실에서 Meta 프로필 사진들과 YouTube 썸네일의 실제 이미지 렌더 확인.
- 실제 Mac 내부 Instagram 페이지 열기(로그인 요구 화면), 브라우저 닫기 후 관제실 자동 복귀 확인.
- 로컬 YouTube 서버 재시작 후 `thumbnail_url` 존재와 실제 채널 연결 확인.

## 주의 및 향후 확인

- Threads의 팔로워 수와 게시물 수는 별도 API 지원·권한 검증 전까지 표시하지 않음.
- Meta 페이지가 기본 프로필 사진을 사용하는 경우 실제 Meta에 설정된 기본 이미지를 그대로 보여주며 임의 브랜드 로고로 대체하지 않음.
- 실제 마이크 발화에 의한 명령 인식은 이번 소스/화면 테스트와 별도로 사용자 현장 테스트가 필요.
