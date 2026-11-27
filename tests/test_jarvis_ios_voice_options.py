"""Guard iPhone-only form of address and explicit credit-based voice opt-in."""
from pathlib import Path
import unittest  # 2026-11-27: 영어 대화·Kokoro Heart 음성으로 갱신 (사용자 요청)

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / 'ios/JARVIS/Sources'


class JARVISIOSVoiceOptionTests(unittest.TestCase):
    def test_mobile_only_address_is_orabeoni(self):
        commands = (IOS / 'JARVISCommand.swift').read_text()
        home = (IOS / 'JARVISHomeView.swift').read_text()
        self.assertIn('안녕하세요 DECHIVE!', home)
        self.assertNotIn('오빠', commands)
        self.assertIn('DECHIVE', commands)
        self.assertNotIn('오라버니', commands)
        self.assertNotIn('JARVIS RESPONSE', home)
        self.assertNotIn('Text("LOCAL")', home)

    def test_mac_uses_its_own_address_and_voice_id(self):
        mac = (ROOT / 'macos/Sources/EidisMac/ElevenLabsVoiceService.swift').read_text()
        self.assertIn('JarvisConversationLanguage.summonGreeting', mac)
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
        # 2026-11-28: 목소리 설정 화면 제거, 유나 하나만 사용
        self.assertNotIn('JARVISVoiceSettingsView(', home)
        self.assertNotIn('Image(systemName: "waveform")', home)


if __name__ == '__main__':
    unittest.main()
