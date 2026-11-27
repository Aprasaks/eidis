"""자비스 단일 목소리(Kokoro Heart)·영어 대화 계약."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAC = ROOT / "macos/Sources/EidisMac"


def read(name):
    return (MAC / name).read_text(encoding="utf-8")


class VoiceEnglish(unittest.TestCase):
    def test_single_voice_route(self):
        kokoro = read("JarvisKokoroVoice.swift")
        self.assertIn('static let voice = "af_heart"', kokoro)
        self.assertIn('env["HF_HUB_OFFLINE"] = "1"', kokoro)
        voice = read("JarvisVoiceService.swift")
        self.assertIn("if JarvisKokoroVoice.shared.isPrimary {", voice)
        self.assertIn("JarvisKokoroVoice.shared.isPlaying", voice)
        eleven = read("ElevenLabsVoiceService.swift")
        self.assertIn("if JarvisKokoroVoice.shared.isPrimary && !explicitlyPreviewed {", eleven)
        server = (ROOT / "tools/kokoro/jarvis_tts_server.py").read_text(encoding="utf-8")
        self.assertIn('HOST, PORT = "127.0.0.1", 8792', server)
        self.assertIn("def log_message(self, *args):", server)

    def test_english_conversation(self):
        lang = read("JarvisConversationLanguage.swift")
        self.assertIn('Locale(identifier: english ? "en-US" : "ko-KR")', lang)
        self.assertIn("Always reply in natural, concise English as JARVIS", lang)
        convo = read("JarvisOverlayConversation.swift")
        self.assertEqual(convo.count("JarvisConversationLanguage.finalDirective"), 2)
        self.assertIn('text.contains("dashboard")', read("JarvisLiveDashboard.swift"))


if __name__ == "__main__":
    unittest.main()
