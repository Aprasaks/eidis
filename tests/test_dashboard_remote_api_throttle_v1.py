"""Guard the actual GitHub/Vercel provider polling policy against regressions."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIVE = (ROOT / "macos/Sources/EidisMac/JarvisLiveDashboard.swift").read_text()
VIEW = (ROOT / "macos/Sources/EidisMac/JarvisCommandCenterView.swift").read_text()
GITHUB = (ROOT / "macos/Sources/EidisMac/JarvisGitHubRemoteScanner.swift").read_text()
VERCEL = (ROOT / "macos/Sources/EidisMac/JarvisVercelRemoteScanner.swift").read_text()


class RemoteThrottleTests(unittest.TestCase):
    def test_fast_local_loop_does_not_set_remote_rate(self):
        self.assertIn("intervalNanoseconds: UInt64 = 7_000_000_000", LIVE)
        self.assertIn("githubRefreshSeconds: TimeInterval = 600", LIVE)
        self.assertIn("vercelRefreshSeconds: TimeInterval = 900", LIVE)
        self.assertIn("Date().timeIntervalSince($0) >= Self.githubRefreshSeconds", LIVE)
        self.assertIn("Date().timeIntervalSince($0) >= Self.vercelRefreshSeconds", LIVE)
        self.assertIn("githubTask == nil", LIVE)
        self.assertIn("vercelTask == nil", LIVE)

    def test_close_and_reopen_cannot_reset_remote_cooldown(self):
        show = LIVE.split("    func show(_ selected:", 1)[1].split(
            "    @discardableResult", 1)[0]
        for invalid in ("githubSnapshot = nil", "githubLastCheckedAt = nil",
                        "vercelSnapshot = nil", "vercelLastCheckedAt = nil"):
            self.assertNotIn(invalid, show)
        for expected in ("latestGitHubAttemptAt = githubLastCheckedAt",
                         "latestVercelAttemptAt = vercelLastCheckedAt",
                         "latestGitHubSnapshot = snapshot",
                         "latestVercelSnapshot = snapshot",
                         "githubSnapshot = Self.latestGitHubSnapshot",
                         "vercelSnapshot = Self.latestVercelSnapshot",
                         "githubLastCheckedAt = Self.latestGitHubAttemptAt",
                         "vercelLastCheckedAt = Self.latestVercelAttemptAt"):
            self.assertIn(expected, LIVE)

    def test_display_explains_freshness_and_does_not_claim_remote_realtime(self):
        self.assertIn('systemRow("로컬 갱신 주기", "약 7초"', VIEW)
        self.assertIn('systemRow("GitHub 원격 조회", "10분 / 캐시 재사용"', VIEW)
        self.assertIn('systemRow("Vercel 원격 조회", "15분 / 캐시 재사용"', VIEW)
        self.assertIn('GitHub는 10분, Vercel은 15분 간격', LIVE)

    def test_provider_scans_remain_read_only(self):
        self.assertIn('"api", "--method", "GET", "--paginate"', GITHUB)
        self.assertIn('["project", "ls", "--format=json"]', VERCEL)
        self.assertIn('["ls", "--format=json"]', VERCEL)
        for forbidden in ('"deploy"', '"rollback"', '"remove"', '"push"', '"delete"'):
            self.assertNotIn(forbidden, GITHUB + VERCEL)


if __name__ == "__main__":
    unittest.main()
