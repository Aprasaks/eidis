"""ElevenLabs may receive text only after a deliberate on-device choice."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
ELEVEN=(ROOT/"macos/Sources/EidisMac/ElevenLabsVoiceService.swift").read_text()
VOICE=(ROOT/"macos/Sources/EidisMac/JarvisVoiceService.swift").read_text()
SPEECH=(ROOT/"macos/Sources/EidisMac/NativeSpeech.swift").read_text()
APP=(ROOT/"macos/Sources/EidisMac/EidisMacApp.swift").read_text()


class ElevenLabsVoiceContract(unittest.TestCase):
    def test_user_supplied_voice_id_and_supported_models(self):
        self.assertIn('static let suggestedVoiceID = "O2KReOFLpoR65nz6C9Se"',ELEVEN)
        self.assertIn('"eleven_flash_v2_5"',ELEVEN)
        self.assertIn('"eleven_multilingual_v2"',ELEVEN)
        self.assertIn("https://api.elevenlabs.io/v1/text-to-speech/",ELEVEN)
        self.assertIn('request.setValue(key, forHTTPHeaderField: "xi-api-key")',ELEVEN)

    def test_key_is_kept_in_keychain_not_preferences_or_plain_source(self):
        self.assertIn("import Security",ELEVEN)
        self.assertIn("SecItemAdd(",ELEVEN)
        self.assertIn("SecItemUpdate(",ELEVEN)
        self.assertIn("SecItemDelete(",ELEVEN)
        self.assertIn("SecItemCopyMatching(",ELEVEN)
        self.assertIn("kSecAttrAccessibleWhenUnlockedThisDeviceOnly",ELEVEN)
        self.assertIn("SecureField(",SPEECH)
        self.assertNotIn('defaults.set(key,',ELEVEN)
        self.assertNotIn('print(key)',ELEVEN)
        self.assertNotIn('logger.info(key)',ELEVEN)

    def test_provider_is_opt_in_cost_bounded_and_falls_back(self):
        self.assertIn("self.enabled = defaults.bool(forKey: Self.enabledKey) && hasSavedKey",ELEVEN)
        self.assertIn("guard (enabled || explicitlyPreviewed) && keyPresent",ELEVEN)
        self.assertIn("private static let maxRequests = 5",ELEVEN)
        self.assertIn("private static let maxCharacters = 600",ELEVEN)
        self.assertIn("attempts += 1",ELEVEN)
        self.assertIn("fallback.speak(phrase)",ELEVEN)
        self.assertIn("URLSessionConfiguration.ephemeral",ELEVEN)
        self.assertNotIn("URLSession.shared",ELEVEN)
        self.assertIn("Button(\"ElevenLabs 미리 듣기 · 크레딧 사용\")",SPEECH)
        self.assertIn("Button(\"연결 확인 · 음성 생성 없음\")",SPEECH)
        self.assertIn("func checkVoiceConnection() async",ELEVEN)
        self.assertIn("request.httpMethod = \"GET\"",ELEVEN)
        self.assertIn("https://api.elevenlabs.io/v1/voices/",ELEVEN)
        self.assertIn('Button("Mac 목소리 미리 듣기")',APP)
        self.assertIn('Button("Mac 음성 미리 듣기")',SPEECH)
        self.assertIn('accessibilityIdentifier("elevenlabs-status")',SPEECH)
        self.assertIn("Toggle(\"이후 자비스 답변을 ElevenLabs로 음성 생성",SPEECH)
        self.assertIn("synthesizer.speak",VOICE)
        self.assertIn("await elevenLabs.speak(answer.spoken, fallback: voice)",SPEECH)
        self.assertIn("NativeSpeechPanel(bridge: bridge, voice: voice, elevenLabs: elevenLabs)",APP)

    def test_no_key_or_voice_content_in_web_storage(self):
        for path in (ROOT/"web").glob("*.js"):
            content=path.read_text(encoding="utf-8")
            self.assertNotIn("xi-api-key",content)
            self.assertNotIn("O2KReOFLpoR65nz6C9Se",content)


if __name__=="__main__":
    unittest.main()
