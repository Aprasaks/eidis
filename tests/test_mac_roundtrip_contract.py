"""Local Mac native command round-trip boundaries and UI contract."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SUT = (ROOT / "macos/Sources/EidisMac/JarvisRoundTrip.swift").read_text("utf-8")
PANEL = (ROOT / "macos/Sources/EidisMac/MacReadinessPanel.swift").read_text("utf-8")
CI = (ROOT / ".github/workflows/ci.yml").read_text("utf-8")


class LocalRoundtripTests(unittest.TestCase):
    def test_local_only_explicit_readonly_action(self):
        self.assertIn('127.0.0.1:8765', SUT)
        self.assertIn('"/api/projects"', SUT)
        self.assertIn('"/api/chat"', SUT)
        self.assertIn('"remote_consent": false', SUT)
        self.assertIn('"자비스, 다음 할 일 뭐야?"', SUT)
        self.assertIn('reply.action == "project_self_overview"', SUT)
        self.assertIn('!reply.executed', SUT)
        self.assertIn('reply.brainSource == "local"', SUT)
        self.assertIn('$0.repoFullName == "Aprasaks/eidis"', SUT)
        for forbidden in ("api.github.com", "git push", "Process()", "NSWorkspace.shared.open",
                          "AVAudioEngine", "requestAuthorization", "AXUIElementPerformAction",
                          "/api/projects/status"):
            self.assertNotIn(forbidden, SUT)

    def test_diagnostic_requires_actual_user_click(self):
        self.assertIn('Button("로컬 텍스트 명령 왕복 점검")', PANEL)
        self.assertIn('diagnostics.verifyLocalTextCommand()', PANEL)
        self.assertIn('commandProof = await JarvisRoundTrip.check()', PANEL)
        self.assertIn('proof.passed', PANEL)
        self.assertIn('proof.testedAt.formatted(', PANEL)
        self.assertIn('commandProof == nil', PANEL)
        self.assertIn("음성·UI", SUT)

    def test_swift_fixture_in_ci(self):
        self.assertIn('macos/tests/roundtrip/main.swift', CI)
        self.assertIn('macos/Sources/EidisMac/JarvisRoundTrip.swift', CI)


if __name__ == "__main__":
    unittest.main()
