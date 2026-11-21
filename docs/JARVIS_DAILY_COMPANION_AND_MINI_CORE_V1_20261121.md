# JARVIS DAILY COMPANION — 현재 연결 상태와 구현 순서
기록: 2026-11-21 / DECHIVE.local 코드 및 로컬 API 확인

## 목표
- 항상 사용할 수 있는 Mac의 조그만 금빛 코어(동의 기반; 기본 비활성화)
- 명시적 호출에 따른 아침 뉴스 브리핑: 출처·발표/조회 시각·불확실성 구분
- 실시간 주식 관심목록/가상투자 현황: 실제 시세·장 상태·조회 시각·지연 여부 구분
- GitHub/Vercel/YouTube/사이트/날씨/일정 데이터 통합

## 현재 확인
- 로컬 Qwen/Ollama, SQLite, 연구 1.1, WebKit Control 1.0 동작하는 로컬 경로 있음.
- GitHub 기존 gh CLI API 읽기 연동, Vercel CLI 최근 배포 조회 구현. GitHub/Vercel 원격 조회는 각각 10분/15분 캐시 간격이며 7초마다 외부 요청 안 함.
- YouTube OAuth status: configured=true connected=true. 실제 로컬 /api/youtube/summary 조회 결과 connected=true, channel_title/analytics 데이터 존재, analytics_error 비어 있음. 이는 조회한 채널 권한 범위의 확인이며 모든 채널을 의미하지 않음.
- Instagram DECHIVE.WIKI: 토큰 저장/검증 및 GET 프로필 조회 기능 구현; 현재 사용자의 실제 Keychain 토큰 유효성 재검증 미실시. 자동으로 연결 완료로 선언하지 않음.
- API 전용 구현 아직 없음: 실시간 국내 증시 시세/호가, 주식 포트폴리오, OpenDART, 뉴스 전용 브리핑, GSC/GA4, Gmail/Calendar/Drive, Notion, Threads/Facebook, 날씨. 현재 Research 1.0의 Bing 공개 RSS 검색은 뉴스 브리핑 전용의 시간별·공식 출처·사실 확인 기능이 아님.

## 이번 구현: MINI CORE 1.0
- macOS MenuBarExtra에 '작은 코어 항상 띄우기/숨기기' 추가.
- 사용자가 켜기 전에는 자동 생성하지 않음. 동의한 설정은 UserDefaults의 bool로 유지되고 앱 재시작 시 자동 복원.
- 코어 패널 크기 230 x 245pt, 기본 위치 현재 화면 visibleFrame 우측 하단 여유 공간(22/24pt). 창 배경을 드래그해 위치 변경 가능(위치 영구 저장 기능은 범위 밖).
- NSPanel floating level, canJoinAllSpaces / fullScreenAuxiliary, hidesOnDeactivate=false. 같은 Mac에서 다른 창 위에 작게 떠 있도록 시도하나 모든 macOS 공간/전용 전체화면 게임/시스템 화면 위에 보인다고 보장하지 않음.
- 작은 코어 클릭 또는 기존 ⌘⌥J: 전체화면으로 전환. 전체화면 전환 시 작은 패널/AVPlayer 해제. 전체화면 Esc 닫을 때 사용자가 켜 놓은 경우 작은 코어 다시 생성.
- 작은 코어 자체는 마이크를 켜지 않음. '자비스' 핫워드 상시 청취 기능 없음. 대화는 전체화면에서 기존 수동/권한 승인된 음성 방식.
- 작은 코어가 열려도 GitHub/Vercel/YouTube 등 외부 API 폴링을 추가로 시작하지 않음.
- 기존 금빛 코어 HD 루프 영상 파일 그대로 재사용하며 별도 이미지 생성/모델 추가 없음.
- 설정·권한·비밀정보·개인 DB의 변경 없음.
- MacBook에서 상시 영상 디코딩은 전력을 사용하므로 후속 버전에서는 저전력 일시정지/정적 프레임 옵션을 검토.

## 다음 실제 API 개발 순서
1. **Morning Briefing**: 사용자가 요청하면 새로 수집된 주요 기사/원문만 묶어 뉴스 브리핑. 기본 2~3개 영역(국내/세계/AI), 특정 시간대(전일 밤~오늘 아침)를 명시. 각각 제목/발행일/기자/원문 링크/확인 시각/중복 보도 구분. 1건의 사실을 여러 복제 기사로 '독립 검증'이라고 잘못 표시하지 않기. 자료 없으면 '신규 주요 기사 확인 불가'. 음성은 최대 몇 분 요약, 화면엔 상세 목록.
2. **Stock Board**: 기본 읽기 전용. KIS Developers 국내주식 시세(현재가 REST, 필요한 경우만 WS), KRX 일별 공식 시장 데이터, OpenDART 공시. 처음엔 종목코드·이름·전일종가·현재가/전일대비/거래량·시세 조회 시각·장 상태·시세 제공자 표시. API 지연 데이터에 '실시간' 표기를 하지 않음. 관심종목과 가상투자를 구분; **실제 주문 기능은 포함하지 않음**.
3. **Personal Ops**: Google Calendar 또는 macOS EventKit 일정, Open-Meteo/KMA 날씨, GitHub Actions/배포, GSC/GA4를 개별 권한으로 추가.
4. **최종 운영**: 대시보드가 열릴 때 7초마다 로컬 UI만 갱신; 원격 API는 각 서비스 쿼터/캐시 정책에 따라 5~30분 및 수동 새로고침. 뉴스는 요청 기반; 거래 중 주식은 시장 데이터 공급자의 허용 빈도 내에서 동작.
5. 장기적으로 작은 코어에서 뉴스/주식/알림을 클릭해 왼쪽 대화 패널과 오른쪽 맞춤 보드 오픈. 진짜 핫워드 감지는 사용자 별도 승인/로컬 개인정보 설계 후 진행.

## 공식 자료(방문 검증한 개발 문서)
- KIS Developers: https://apiportal.koreainvestment.com/apiservice-summary
- KRX Open API: https://openapi.krx.co.kr/contents/OPP/INFO/service/OPPINFO004.cmd
- OpenDART: https://opendart.fss.or.kr/intro/main.do
- Apple NSWindow canJoinAllSpaces: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces

## 검증
- Python 전체 회귀, Swift 앱 빌드, 서명, 설치 전 앱 백업, 개인 DB 무결성 점검은 별도 빌드 기록.
- 작은 코어 버튼 실제 사용 및 여러 Spaces/모니터 상시 표시, 배터리/CPU 부하는 사용자 화면에서 실기기 확인 필요.
