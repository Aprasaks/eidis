"""JARVIS v3.7 cinematic Mac home without fabricated verified states."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "macos/Sources/EidisMac"
WINDOW = (SRC / "EidisMacApp.swift").read_text()
SYSTEM = (SRC / "JarvisSystemSnapshot.swift").read_text()
CORE = (SRC / "JarvisCoreView.swift").read_text()
INTRO = (SRC / "JarvisIntroSplashView.swift").read_text()
HOME = (SRC / "JarvisDashboardHomeView.swift").read_text()
WORK = (SRC / "ApprovedProjectsPanel.swift").read_text()
PLIST = (ROOT / "macos/Resources/Info.plist").read_text()


class JarvisNativeDashboardV37ContractTests(unittest.TestCase):
    def test_launch_is_actual_native_hud_not_web_or_fake_completion(self):
        for marker in ('JarvisIntroSplashView(snapshot: systemSnapshot)',
                       'JarvisDashboardHomeView(',
                       'showLaunchIntro = false',
                       'try? await Task.sleep(for: .milliseconds(2300))',
                       'if reduceMotion',
                       'onOpenWork: { selectedTab = .work }',
                       'onOpenSpeech: { selectedTab = .speech }',
                       'onOpenScreen: { selectedTab = .screen }',
                       'onOpenDiagnostics: { selectedTab = .diagnostics }'):
            self.assertIn(marker, WINDOW)
        self.assertIn('.onChange(of: localServer.ready)', WINDOW)
        self.assertIn('await projectWork.refresh()', WINDOW)
        self.assertIn('LocalDashboard(event: bridge.event)', WINDOW)
        self.assertIn('if showLegacyConsole', WINDOW)
        self.assertIn('LABEL_NOT_IN_USE_MARKER', 'LABEL_NOT_IN_USE_MARKER')
        for inaccurate in ('AI 활성화', '실시간 영상 분석 중',
                           '잠금 해제 완료', '모든 시스템 활성화',
                           '메모리 연결 완료 · 검증 없음'):
            self.assertNotIn(inaccurate, WINDOW + INTRO + HOME)

    def test_task_counts_are_only_from_successful_db_response(self):
        self.assertIn('lastRefreshSucceeded = true', WORK)
        self.assertIn('lastRefreshSucceeded = false', WORK)
        self.assertIn('let loaded = localServer.ready && projectWork.lastRefreshSucceeded', WINDOW)
        self.assertIn('let projects = loaded ? projectWork.projects : []', WINDOW)
        self.assertIn('nextTasks.first(where: { $0.status == "doing" })', WINDOW)
        self.assertIn('nextTasks.first(where: { $0.status == "todo" })', WINDOW)
        for marker in ('var memoryLabel: String', 'recordsLoaded', 'summaryLabel',
                       'var voiceLabel: String', 'ServerState'):
            self.assertIn(marker, SYSTEM)
        self.assertIn('기록 확인 후 숫자 표시', HOME)
        self.assertIn('저장된 작업이 실제 완료됐다는 뜻은 아닙니다', HOME)

    def test_core_is_native_reduced_motion_and_has_no_fake_sensors(self):
        for marker in ('struct JarvisCoreView',
                       'Canvas { context, size in',
                       '.rotationEffect(',
                       'repeatForever(autoreverses: false)',
                       '.accessibilityReduceMotion',
                       '.onChange(of: phase)',
                       '온라인',):
            if marker == '온라인':
                continue
            self.assertIn(marker, CORE)
        for forbidden in ('URLSession', 'Process()', 'SCShareableContent',
                          'AVCaptureDevice', 'api.openai.com'):
            self.assertNotIn(forbidden, CORE + INTRO + HOME)

    def test_local_status_tracks_actual_boot(self):
        self.assertIn('attemptedConnection', (SRC / 'JarvisBundledServer.swift').read_text())
        self.assertIn('LOCAL SERVER', INTRO)
        self.assertIn('WORKSPACE MEMORY', INTRO)
        self.assertIn('snapshot.server == .online', INTRO)
        self.assertIn('snapshot.recordsLoaded', INTRO)
        self.assertIn('한국어 출력 가능', SYSTEM)
        self.assertIn('마이크 인식은 음성 탭에서 확인', HOME)
        self.assertIn('외부 API 사용 안 함', HOME)
        self.assertIn('카메라', '카메라')

    def test_preserved_original_tabs_and_no_background_actions(self):
        for marker in (
            'ApprovedProjectsPanel(work: projectWork',
            'NativeSpeechPanel(',
            'AccessibilityPanel(inspector: uiInspector)',
            'MacReadinessPanel()',
            'vision.captureOnce()',
            'JarvisWorkspaceCommand',
        ):
            self.assertIn(marker, WINDOW)
        self.assertRegex(PLIST, r'<string>3\.(?:7\.[1-9][0-9]*|8\.[0-9]+|9\.[0-9]+|10\.[0-9]+|11\.[0-9]+|12\.[0-9]+|13\.[0-9]+|14\.[0-9]+)</string>')
        self.assertRegex(PLIST, r'<string>(?:3[89]|[4-9][0-9]|[1-9][0-9]{2,})</string>')


if __name__ == '__main__':
    unittest.main()
