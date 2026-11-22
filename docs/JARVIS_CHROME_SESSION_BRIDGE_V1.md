# JARVIS Chrome 세션 연동 v1 — 2026-11-22

## 현상과 목표

기존 JARVIS 내부 SNS 탭은 `WKWebsiteDataStore.nonPersistent()`를 사용했기 때문에 Chrome의 로그인 쿠키·세션과 별개입니다. Instagram은 내부 WebKit에서 로그인 화면으로 이동했습니다. 이를 해결하기 위해 기존 Chrome 사용자의 승인된 로그인 세션에서 DECHIVE SNS 프로필을 여는 경로와 별도 읽기 전용 Chrome DevTools MCP 진단을 구현합니다.

## 제공 기능

1. 명시적 계정 열기 요청(음성 또는 클릭): `인스타 열어봐`, `스레드 열어봐`, `페이스북 열어봐`, `유튜브 열어봐`는 **실제 Google Chrome**(`com.google.Chrome`)에서 해당 계정의 고정 공식 HTTPS 프로필을 엽니다. Google Chrome이 없는 경우 실패 처리하며 WKWebView나 새 로그인 세션으로 우회하지 않습니다.
2. Mac의 스크린세이버 레벨 전체 화면은 Chrome이 URL 열기를 수락한 **후** 내려와 실제 Chrome이 보이도록 합니다. 앱은 실행 중이고, 기존 단축키로 JARVIS를 다시 열 수 있습니다. 작은 코어가 사용 설정되어 있으면 기존 정책대로 표시합니다.
3. META 카드의 `Chrome 세션 확인` 버튼은 사용자가 직접 누른 경우에만 별도의 로컬 Node Chrome DevTools MCP 프로세스를 실행합니다. Chrome 144+에서 사용자가 **chrome://inspect/#remote-debugging**의 원격 디버깅을 켜고, Chrome 권한 팝업에서 직접 허용해야 합니다. 팝업이 보이도록 전체 화면 오버레이 레벨을 일시적으로 낮췄다가 진단 후 복원합니다.
4. MCP 진단에 사용하는 동작은 `list_pages` **한 번뿐**입니다. 본문·비밀번호·쿠키·스토리지·네트워크 요청·스크린샷 등은 수집/반환하지 않습니다. 브리지 정책은 실제 화면에 열린 DECHIVE 4개 공식 채널 URL의 **존재 여부만** 반환하며, 다른 탭 주소/제목은 로그/결과에 내보내지 않습니다. 개인 계정의 모든 탭에 접근할 수 있는 높은 브라우저 권한이므로 사용자 승인 없이 실행하지 않습니다.
5. 현재 버전은 **자동 게시/삭제/광고/DM 전송**이나 프로필 전체 페이지를 자비스 안으로 끼워 넣는 기능은 제공하지 않습니다. Chrome의 별도 창이 열리는 것이 실제 동작이며, 이미 연결된 Meta 공식 API는 대시보드 지표를 위해 계속 사용합니다.

## Chrome DevTools MCP 환경

- `chrome-devtools-mcp@1.13.0`, `@modelcontextprotocol/sdk@1.32.2` 버전을 package-lock으로 고정했습니다.
- 앱 배포본에는 `tools/chrome-bridge/check.mjs` / `policy.mjs`와 라이브러리만 번들링합니다. Chrome 프로필·토큰·인증 DB를 복사하지 않습니다.
- `--autoConnect`로 사용 중인 Chrome 연결만 시도, 새 브라우저/프로필 생성 없음.
- JS 직접 실행/입력/네트워크/디버깅/파일 내비게이션 등 불필요한 MCP 도구는 비활성화하고 사용량 통계 및 CrUX도 끕니다. 그래도 기저 접근 권한은 광범위합니다.
- 각 검사 실행 시간 35초, 상위 프로세스 42초 제한, 출력 4KiB 제한.

## 검증

- Google Chrome 157 사용 중 확인.
- 실제 설치 앱에서 Instagram 프로필 열기 버튼을 눌러 기존 Chrome에서 `www.instagram.com/dechive.wiki/`가 열리고, 브라우저 화면에서 **로그인된 계정 프로필**이 표시되는 것을 확인. 실제 Chrome에는 프로필 편집 및 게시물 정보가 노출됐고 별도 쿠키 이관/비밀번호 입력 없이 동작함.
- Chrome URL 핀 검사 Swift 스모크 테스트 6/6, Node 필터 정책 테스트 12건, Python 전체 테스트 통과.
- MCP 자체는 Chrome 원격 디버깅이 비활성/미승인된 상태에서 `connected:false`를 반환하며, **승인 전 실제 탭 연결 성공으로 표시하지 않음**.

## 사용자 연결 절차

1. Chrome의 `chrome://inspect/#remote-debugging` 화면에서 Remote Debugging을 직접 활성화.
2. JARVIS 통합 대시보드 META 카드의 `Chrome 세션 확인` 클릭.
3. Chrome의 연결 허용 팝업을 사용자가 직접 확인·승인.
4. JARVIS 카드에서 `Chrome 접근 확인` 상태로 바뀌었는지 확인. 로그인된 Chrome의 다른 탭 정보는 자비스 카드에 노출되지 않음.

## 한계

- Chrome에서 사용자 지정 프로필을 여러 개 쓸 때, 네이티브 URL 열기는 Chrome의 현재 기본/활성 프로필을 사용하므로, 대상 SNS 로그인이 없는 프로필이면 사용자가 그 Chrome 프로필에서 직접 로그인해야 합니다.
- 이 기능으로 Chrome 화면이 자비스의 SwiftUI 패널 안에 임베드되지는 않습니다. Chrome WebContents의 직접 임베딩은 지원되는 API가 아니며, Chrome DevTools MCP는 접근/제어용 API입니다.
- MCP 읽기/조작 기능 확대는 별도 설계·사용자 동의·사이트별 허용 범위·작업별 승인 절차가 필요합니다.
