"""승인된 캐러셀 Instagram 자동 게시 계약 (소스 텍스트 기준)."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / "macos/Sources/EidisMac/JarvisInstagramPublisher.swift").read_text(encoding="utf-8")
RUNNER = (ROOT / "macos/Sources/EidisMac/JarvisCarouselRunner.swift").read_text(encoding="utf-8")


class InstagramPublisherContract(unittest.TestCase):
    def test_only_approved_and_unchanged(self):
        self.assertIn('Self.status(of: dir) == "approved"', SRC)
        self.assertIn("JarvisCarouselRunner.contentDigest(of: dir) == approved", SRC)

    def test_golden_time_once_per_day_no_blind_retry(self):
        self.assertIn("(22 * 60 ..< 23 * 60 + 30).contains(minutes)", SRC)
        self.assertIn('Self.record($0)?["day"] as? String == today', SRC)
        self.assertIn('previous["result"] as? String == "publishing"', SRC)

    def test_public_folder_is_temporary_and_narrow(self):
        self.assertIn('"^slide-[0-9]{2}\\\\.jpg$"', SRC)
        self.assertIn('params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1"', SRC)
        self.assertIn("await closePublicFolder()\n        finish(outcome.0, outcome.1)", SRC)
        self.assertIn("timeout: Double = 15", SRC)
        self.assertIn('["funnel", "--https=443", "off"]', SRC)

    def test_token_only_in_header(self):
        self.assertIn('req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")', SRC)
        self.assertNotIn("access_token=", SRC)
        self.assertNotIn("NSLog(token", SRC)

    def test_scheduler_wired_and_posted_marked(self):
        self.assertIn("JarvisInstagramPublisher.shared.startSchedule()", RUNNER)
        self.assertIn('saved.status = "posted"', RUNNER)


if __name__ == "__main__":
    unittest.main()
