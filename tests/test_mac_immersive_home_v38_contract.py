"""JARVIS Mac v3.8 immersive first screen and non-destructive mode toggle."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "macos/Sources/EidisMac"
APP = (SRC / "EidisMacApp.swift").read_text()
IMMERSIVE = (SRC / "JarvisImmersiveHomeView.swift").read_text()
CORE = (SRC / "JarvisCoreView.swift").read_text()
HOLOGRAM = (SRC / "JarvisHologramView.swift").read_text()
MODEL = (SRC / "JarvisSystemSnapshot.swift").read_text()
PLIST = (ROOT / "macos/Resources/Info.plist").read_text()


class JarvisImmersiveHomeContracts(unittest.TestCase):
    def test_installed_mac_launch_defaults_to_immersive(self):
        self.assertIn('@AppStorage("JARVIS_CinematicHome_Enabled") private var cinematicHome = true', APP)
        self.assertIn('if cinematicHome {', APP)
        self.assertIn('JarvisImmersiveHomeView(', APP)
        self.assertIn('onShowDashboard: { cinematicHome = false }', APP)
        self.assertIn('onRefresh: { refreshDashboard() }', APP)
        self.assertIn('Button("상태 갱신", action: onRefresh)', IMMERSIVE)
        self.assertIn('if selectedTab == .assistant && cinematicHome', APP)
        self.assertIn('cinematicHome = true', APP)
        self.assertIn('JarvisDashboardHomeView(', APP)
        self.assertIn('showLegacyConsole = false', APP)

    def test_existing_native_features_still_available(self):
        for item in ('selectedTab = .work', 'selectedTab = .speech',
                     'selectedTab = .screen', 'selectedTab = .diagnostics',
                     'ApprovedProjectsPanel(', 'NativeSpeechPanel(',
                     'LocalDashboard(event: bridge.event)', 'JarvisIntroSplashView('):
            self.assertIn(item, APP)
        for item in ('onOpenWork', 'onOpenSpeech', 'onOpenScreen',
                     'onOpenDiagnostics', 'onShowDashboard'):
            self.assertIn(item, IMMERSIVE)

    def test_core_is_native_and_obeys_accessibility(self):
        self.assertIn('JarvisHologramView(animated: !reduceMotion && phase == .active)', IMMERSIVE)
        self.assertIn('SCNView', HOLOGRAM)
        self.assertIn('SCNTorus', HOLOGRAM)
        self.assertIn('SCNGeometrySource(vertices:', HOLOGRAM)
        self.assertNotIn('wires.fillMode = .lines', HOLOGRAM)
        self.assertNotIn('SCNSphere(radius: 1.22)', HOLOGRAM)
        self.assertIn('repeatForever', HOLOGRAM)
        self.assertIn('view.isPlaying = animated', HOLOGRAM)
        self.assertIn('accessibilityReduceMotion', CORE)
        self.assertIn('phase == .active', CORE)
        self.assertIn('repeatForever(autoreverses: false)', CORE)
        for bad in ('VideoPlayer(', 'AVPlayer(', 'WKWebView(', 'http://',
                    'URLSession.shared', 'api.openai.com', 'try!'):
            self.assertNotIn(bad, IMMERSIVE)

    def test_no_unverified_live_status_claims(self):
        self.assertIn('snapshot.server == .online', IMMERSIVE)
        self.assertIn('snapshot.summaryLabel', IMMERSIVE)
        self.assertIn('음성 입력은 직접 시작', IMMERSIVE)
        self.assertNotIn('항상 듣고 있어', IMMERSIVE)
        self.assertIn('서버 연결 필요', MODEL)
        self.assertIn('기록 확인 전', MODEL)
        for bad in ('실시간 카메라 분석 중', '음성 듣는 중',
                    '일정 동기화 완료', '실시간 날씨', '자동 배포 완료'):
            self.assertNotIn(bad, IMMERSIVE)

    def test_release_version(self):
        self.assertIn('<string>3.9.3</string>', PLIST)
        self.assertIn('<string>47</string>', PLIST)
        self.assertIn('<string>dev.dechive.eidis</string>', PLIST)


if __name__ == '__main__':
    unittest.main()
