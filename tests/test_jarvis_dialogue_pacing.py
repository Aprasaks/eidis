"""Bounded voice pacing and grounded replies; no real API requests in tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT/"macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
TTS = (ROOT/"macos/Sources/EidisMac/ElevenLabsVoiceService.swift").read_text()
UI = (ROOT/"macos/Sources/EidisMac/JarvisLiveDialoguePanel.swift").read_text()
COMMAND = (ROOT/"macos/Sources/EidisMac/JarvisCommandEngine.swift").read_text()

class DialoguePacingContract(unittest.TestCase):
    def test_pause_can_be_set_without_guessing_what_was_said(self):
        self.assertIn("savedPause ?? 1.8", CHAT)
        self.assertIn("min(max(silenceWaitSeconds, 1.2), 8.0)", CHAT)
        self.assertIn(">= self.silenceWaitSeconds", CHAT)
        self.assertIn("self.listener.finish()", CHAT)
        self.assertNotIn("jarvis-live-dialogue-pause-length", UI)
        self.assertNotIn('Toggle(isOn: $dialogue.autoTurnEnabled)', UI)

    def test_elevenlabs_speed_is_configurable_and_safe(self):
        self.assertIn('savedResponseSpeed ?? 0.90', TTS)
        self.assertIn('min(max(responseSpeed, 0.8), 1.05)', TTS)
        self.assertIn('"voice_settings": ["speed": isSummonGreeting ? 1.0 : responseSpeed]', TTS)
        self.assertNotIn('jarvis-live-dialogue-voice-speed', UI)
        self.assertIn('fallback.speak(phrase)', TTS)
        self.assertIn('generation == speechGeneration', TTS)
    
    def test_clarify_unclear_partial_question_do_not_fabricate(self):
        self.assertIn('음성 인식 문장이 잘리거나 의미가 불명확하면', COMMAND)
        self.assertIn('연결되지 않은 API나 실제로 조회하지 않은 데이터를', COMMAND)
        self.assertIn('think": false', CHAT)

if __name__ == "__main__":
    unittest.main()
