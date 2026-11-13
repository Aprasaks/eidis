"""Native voice selector must remain local, optional and shared across replies."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOICE = ROOT / "macos/Sources/EidisMac/JarvisVoiceService.swift"
SPEECH = ROOT / "macos/Sources/EidisMac/NativeSpeech.swift"
APP = ROOT / "macos/Sources/EidisMac/EidisMacApp.swift"

class VoiceSettingsContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.voice = VOICE.read_text(encoding="utf-8")
        cls.speech = SPEECH.read_text(encoding="utf-8")
        cls.app = APP.read_text(encoding="utf-8")

    def test_system_voices_and_local_settings(self):
        self.assertIn("AVSpeechSynthesisVoice.speechVoices()", self.voice)
        self.assertIn('$0.language == "ko-KR"', self.voice)
        self.assertIn("UserDefaults", self.voice)
        for symbol in ("voiceID", "speed", "pitch"):
            self.assertIn("var "+symbol, self.voice)
        self.assertIn("AVSpeechSynthesisVoice(identifier: voiceID)", self.voice)
        self.assertIn("utterance.pitchMultiplier", self.voice)
        self.assertIn("utterance.rate", self.voice)
        self.assertNotIn("http://", self.voice)
        self.assertNotIn("https://", self.voice)

    def test_playback_uses_same_settings_for_wake_and_command(self):
        self.assertIn("private var voice", self.app)
        self.assertIn("JarvisVoiceService()", self.app)
        self.assertIn("voice.preview()", self.app)
        self.assertIn("NativeSpeechPanel(bridge: bridge, voice: voice)", self.app)
        self.assertIn("voice.speak(answer.spoken)", self.speech)
        self.assertNotIn("let speaker = AVSpeechSynthesizer()", self.speech)

    def test_ui_has_preview_and_controls(self):
        for text in (
            'GroupBox("자비스 목소리")', 'Picker("목소리", selection: $voice.voiceID)',
            'Button("미리 듣기")', 'Button("초기화")',
            'Slider(value: $voice.speed', 'Slider(value: $voice.pitch'
        ):
            self.assertIn(text, self.speech)
        self.assertIn("ScrollView {", self.speech)

if __name__ == "__main__":
    unittest.main()
