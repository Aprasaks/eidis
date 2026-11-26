"""Opening a dashboard should not narrate routine refresh intervals."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIVE = (ROOT/'macos/Sources/EidisMac/JarvisLiveDashboard.swift').read_text()
CONVERSATION = (ROOT/'macos/Sources/EidisMac/JarvisOverlayConversation.swift').read_text()
VIEW = (ROOT/'macos/Sources/EidisMac/JarvisCommandCenterView.swift').read_text()

class DashboardVoiceContract(unittest.TestCase):
    def test_generic_overview_handoff_is_exact_and_short(self):
        show = LIVE.split('func show(_ selected: JarvisLiveDashboardMode)', 1)[1].split(
            '@discardableResult', 1)[0]
        self.assertIn('selected == .overview', show)
        self.assertIn('"필요한 대시보드를 알려주세요."', show)
        self.assertNotIn('로컬 데이터는 약 7초마다', show)
        self.assertNotIn('GitHub는 10분, Vercel은 15분 간격', show)

    def test_named_view_is_acknowledged_without_asking_again(self):
        show = LIVE.split('func show(_ selected: JarvisLiveDashboardMode)', 1)[1].split(
            '@discardableResult', 1)[0]
        self.assertIn('"\(selected.koreanName) 대시보드를 열었습니다."', show)

    def test_error_still_disclosed_and_actual_refresh_unchanged(self):
        self.assertIn('일부 데이터를 가져오지 못했습니다. 연결 상태를 표시했습니다.', LIVE)
        self.assertIn('intervalNanoseconds: UInt64 = 7_000_000_000', LIVE)
        self.assertIn('githubRefreshSeconds: TimeInterval = 600', LIVE)
        self.assertIn('vercelRefreshSeconds: TimeInterval = 900', LIVE)
        self.assertIn('systemRow("로컬 갱신 주기", "약 7초"', VIEW)
        self.assertIn('outcome = await liveDashboard.show(mode)', CONVERSATION)

if __name__ == '__main__': unittest.main()
