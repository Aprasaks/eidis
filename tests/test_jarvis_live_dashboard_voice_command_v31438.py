"""Explicit natural voice command for the fullscreen live dashboard."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT / "macos/Sources/EidisMac"
ROUTER=(SRC / "JarvisLiveDashboard.swift").read_text()
DIALOGUE=(SRC / "JarvisOverlayConversation.swift").read_text()
VOICE=(SRC / "ElevenLabsVoiceService.swift").read_text()

class LiveDashboardVoiceCommand(unittest.TestCase):
    def test_canonical_phrase_and_speech_recognition_spellings(self):
        self.assertIn('"실시간대시보드"', ROUTER)
        self.assertIn('"실시간대쉬보드"', ROUTER)
        self.assertIn('"실시간데시보드"', ROUTER)
        self.assertIn('if liveBoard && liveBoardNegated { return nil }', ROUTER)
        self.assertIn('return .show(.overview)', ROUTER)

    def test_wake_acknowledges_then_listens_again(self):
        self.assertIn('answer = "네 오빠"', DIALOGUE)
        self.assertIn('private static let wakeAcknowledgment = "네 오빠"', VOICE)
        wake = DIALOGUE.split('func beginDekaWakeTurn()', 1)[1].split('func prepareMiniStandby()',1)[0]
        self.assertIn('self.activateListening()',wake)

    def test_request_uses_existing_dashboard_without_qwen_guess(self):
        plan=DIALOGUE.split('private func planAndRespond(',1)[1]
        self.assertIn('if let liveIntent = JarvisLiveDashboardIntent.parse(prompt)',plan)
        self.assertIn('outcome = await liveDashboard.show(mode)',plan)
        self.assertIn('case .show(let mode):',plan)
        self.assertIn('let explicitlyOpen = ["열어", "띄워", "켜줘", "실행해"]', DIALOGUE)

if __name__=='__main__':
    unittest.main()
