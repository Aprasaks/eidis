"""Guard iPhone-only form of address and explicit credit-based voice opt-in."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / 'ios/JARVIS/Sources'


class JARVISIOSVoiceOptionTests(unittest.TestCase):
    def test_mobile_only_address_is_orabeoni(self):
        commands = (IOS / 'JARVISCommand.swift').read_text()
        home = (IOS / 'JARVISHomeView.swift').read_text()
        self.assertIn('안녕하세요 오라버니!', home)
        self.assertNotIn('오빠', commands)
        self.assertIn('오라버니', commands)
        self.assertNotIn('JARVIS RESPONSE', home)
        self.assertNotIn('Text("LOCAL")', home)

    def test_mac_uses_its_own_address_and_voice_id(self):
        mac = (ROOT / 'macos/Sources/EidisMac/ElevenLabsVoiceService.swift').read_text()
        self.assertIn('"오빠, 뭘 도와드릴까요?"', mac)
        mobile = (IOS / 'JARVISMobileElevenLabs.swift').read_text()
        self.assertIn('"6Vgh4FaCc0SCcWPwcyXa"', mobile)
        self.assertIn('"eleven_flash_v2_5"', mobile)

    def test_private_keychain_and_paid_opt_in(self):
        mobile = (IOS / 'JARVISMobileElevenLabs.swift').read_text()
        self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly', mobile)
        self.assertIn('enabled = isConfigured && defaults.bool', mobile)
        self.assertIn('guard enabled, !isGenerating', mobile)
        self.assertIn('https://api.elevenlabs.io/v1/text-to-speech/', mobile)
        self.assertIn('generatedRequests += 1', mobile)
        settings = (IOS / 'JARVISVoiceSettingsView.swift').read_text()
        self.assertIn('SecureField(', settings)
        self.assertIn('크레딧', settings)
        self.assertIn('저장된 API 키 삭제', settings)
        home = (IOS / 'JARVISHomeView.swift').read_text()
        self.assertIn('JARVISVoiceSettingsView(service: voice.elevenLabs)', home)


if __name__ == '__main__':
    unittest.main()
