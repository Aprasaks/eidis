# JARVIS 모바일 원격 연결 작업 기록

기준: 2026-11-26 23:31 KST
Mac v3.14.50 / iOS v0.4.6 build 15

## 확인된 사실
- 기존 12자리 기기 등록 및 Keychain 저장, iPhone 종료 후 자동 재연결 확인.
- Mac과 iPhone Tailscale 연결 완료.
- 23:28:32 KST LTE 환경에서 사용자 화면으로 암호화된 원격 프로젝트 조회 성공 확인.
- Mac 전용 원격 리스너는 Tailscale IPv4 주소에만 바인딩됨. 기존 로컬 HTTP 서버 공개 금지.
- iOS 연결 상태 구분, 원격 전용 테스트, 기록 시간 표시 개선. 서명 빌드 및 실제 설치/실행 성공.
- 새 UI의 실제 사용자 화면 확인은 아직 필요.
- 현재 원격 통신은 프로젝트 읽기 전용. 일정 변경, 발행, 업무 지시 불가.

## 작업 순서
1. iOS v0.4.6 UI 실기기 확인: LTE, 원격 전용, Wi-Fi 복귀, VPN 일시 해제/재연결, 앱 재시작. 마지막 조회와 실시간 연결 상태를 구별. 원격 전용 해제 후 근거리 복귀 검증.
2. 11월 27일 00:00~01:00 KST 야간 집필 실제 실행 검증. 최대 3회 시작, 초안 검토 등록만. 자동 공개 금지. Mac 전원/앱 실행 유지.
3. 원격 원고 발행 승인: 등록된 기기 인증, 명시적 승인, slug/rev 검증, 중복 요청/재전송 방어, 공통 발행 잠금, 실제 CMS/사이트 확인 및 결과 기록. 테스트는 가짜 발행 핸들러 또는 검토 전용 데이터로 진행하고 승인 없는 실제 발행 금지.
4. APNs: Apple Developer 멤버십 활성화 및 유효한 push entitlement 확인 후 토큰 등록, 키 안전 보관, 실제 잠금 화면 알림 검증. 알림 탭으로 프로젝트 이동. 알림 수신은 Tailscale 원격 조회와 별도.
5. 원격 일정 동기화: 기존 충돌 처리 및 로컬 원본 보호 유지.
6. 원격 음성/텍스트 업무 요청: 허용된 명령만, 상태 및 결과 확인, 고위험 변경은 명시적 승인.

## 안전 및 미검증
- 양쪽 Tailscale 주소는 현재 설치 전용 고정 값. 장치 교체/주소 변경 대응 및 접근 정책 점검 필요.
- 원격 조회 상태는 요청 응답 확인이며 지속 연결을 보장하지 않음.
- Apple Developer 실제 활성화 상태는 최신 재확인 필요. 기존 프로필에 APNs 권한 없음.
- 야간 자동화는 앱 생명주기에 연결되어 있으나 실제 자정 실행 전.
- 불필요한 기능 추가, 자동 공개, 기존 기억 삭제, 임의 결제 금지.

## 23:42 원격 발행 구현 업데이트
- Mac v3.14.51 (125), iOS v0.4.7 (16): 서명 빌드 및 실기기 설치/실행 확인.
- 기존 기기 인증 및 AES-GCM 원격 프로토콜 위에 원고 승인 발행 요청 추가. 기존 근거리 발행과 동일한 검증 스크립트와 단일 프로세스 잠금 사용. 허용된 요청만 처리. slug/rev/명시적 승인 검사, 요청 시각 및 ID 재사용 방지, 기존 CMS 원자적 create/리비전 검사 유지.
- 아이폰 검토 화면에서 별도 실제 공개 확인 단계 추가. 결과 미확인 시 자동 재전송 없음.
- 기존 보안/모바일/야간 및 원격 테스트 13개 통과. 이미 공개된 데이터 증강 글에 대해 CMS check 모드 ALREADY_PUBLIC 확인. 테스트에서 실제 신규 공개 실행하지 않음.
- 새 버전 원격 발행 전체 흐름은 첫 실제 검토 원고에서 사람 승인 후 검증 필요. 원격 일정 동기화, 음성 지시, APNs 미구현.
- Mac 재실행 직후 전용 포트 바인딩 지연이 있었으나 23:41:37 정상 LISTEN 확인.
- 자정 자동화는 기존 코드 유지. 실제 야간 시작 및 결과는 아직 미검증.

## 2026-11-27 00:33 KST 집필/복구 한도 분리
- Mac v3.14.53 build 127, iOS v0.4.9 build 18 설치/실행 완료. 11월 28일 KST부터 신규 집필 최대 3회, 별도 복구 하루 최대 3회 및 주제별 하루 한 번, 검토 등록 목표 3편, 기존 00:00~01:00 및 검수/사람 승인 유지. 오늘 기록과 2건의 검토 초안 보존, 재실행 금지. 실제 Swift 파일 예약 테스트 및 기존 계약 테스트 통과. 다음 야간 근무 실동작 검증 필요.

## Local build configuration
Private Tailnet IPv4 addresses are stored only in ignored ios/JARVISRemote.local.xcconfig. Set JARVIS_REMOTE_MAC and JARVIS_REMOTE_PHONE for the enrolled devices. The macOS packaging script and iOS target consume the same values. Missing or invalid addresses disable the remote route; nearby pairing remains available. Never commit the local override or pairing keys.
