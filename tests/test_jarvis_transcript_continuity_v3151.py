"""Regression contract for speech segments after pauses; hardware testing is separate."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEECH = (ROOT/"macos/Sources/EidisMac/NativeSpeech.swift").read_text()
ACCUM = (ROOT/"macos/Sources/EidisMac/LocalSpeechDecision.swift").read_text()
CHAT = (ROOT/"macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
PANEL = (ROOT/"macos/Sources/EidisMac/JarvisLiveDialoguePanel.swift").read_text()
SMOKE = (ROOT/"macos/tests/voice/main.swift").read_text()

class SpeechContinuityContract(unittest.TestCase):
    def test_committed_segments_are_retained_and_tested(self):
        for snippet in ("struct JarvisSpeechTranscriptAssembler",
                        "private(set) var confirmedSegments",
                        "private(set) var currentPartial",
                        "if isFinal {",
                        "confirmedSegments.append(text)",
                        "currentPartial = text",
                        '.joined(separator: " ")'):
            self.assertIn(snippet, ACCUM)
        self.assertIn('ongoing.receive("자비스 오늘 아침에는", isFinal: true)', SMOKE)
        self.assertIn('ongoing.receive("잠깐 쉬었고", isFinal: false)', SMOKE)

    def test_listener_restarts_recognition_without_restarting_audio_capture(self):
        self.assertIn("private func beginRecognitionSegment(session: UUID)", SPEECH)
        self.assertIn("if result.isFinal {", SPEECH)
        self.assertIn("self.beginRecognitionSegment(session: session)", SPEECH)
        self.assertIn("recognitionEpoch == epoch", SPEECH)
        self.assertIn("self.transcript = self.assembled.receive(", SPEECH)
        self.assertIn("audioRelay.replace(with: request)", SPEECH)
        self.assertIn("input.installTap(onBus: 0", SPEECH)
        self.assertIn("let relay = audioRelay", SPEECH)
        self.assertIn("assembled.reset()", SPEECH)
        self.assertIn("sessionId = UUID()", SPEECH)

    def test_longer_pause_and_manual_finish_mode(self):
        self.assertIn("savedPause ?? 6.5", CHAT)
        self.assertIn("min(max(silenceWaitSeconds, 5.0), 12.0)", CHAT)
        self.assertIn(">= self.silenceWaitSeconds", CHAT)
        self.assertIn('Toggle(isOn: $dialogue.autoTurnEnabled)', PANEL)
        self.assertIn("긴 이야기는 자동 확정을 끄고 Space로 끝내세요", PANEL)

if __name__ == "__main__":
    unittest.main()
