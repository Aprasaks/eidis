"""Keep all live JARVIS utterances and system instructions on the owner-approved address."""
from pathlib import Path
import unittest  # 2026-11-27: 영어 대화·Kokoro Heart 음성으로 갱신 (사용자 요청)

ROOT = Path(__file__).resolve().parents[1]


class OwnerAddressContract(unittest.TestCase):
    def test_old_address_absent_from_live_sources(self):
        # Historical markdown notes and archived user records are not rewritten.
        for directory in ('macos/Sources/EidisMac', 'jarvis', 'web'):
            for path in (ROOT / directory).rglob('*'):
                if not path.is_file() or path.suffix not in ('.swift', '.py', '.html', '.js'):
                    continue
                with self.subTest(file=str(path.relative_to(ROOT))):
                    self.assertNotIn('주인님', path.read_text(encoding='utf-8'))

    def test_known_greetings_and_fixed_address(self):
        sources = ROOT / 'macos/Sources/EidisMac'
        eleven = (sources / 'ElevenLabsVoiceService.swift').read_text()
        dialogue = (sources / 'JarvisOverlayConversation.swift').read_text()
        command = (sources / 'JarvisCommandEngine.swift').read_text()
        profile = (sources / 'JarvisPersonalProfile.swift').read_text()
        panel = (sources / 'JarvisLiveDialoguePanel.swift').read_text()
        self.assertIn('JarvisConversationLanguage.summonGreeting', eleven)
        self.assertIn('answer = "네 오빠"', dialogue)
        self.assertIn('answer = "오빠, 뭘 도와드릴까요?"', dialogue)
        self.assertIn("예외 없이 '오빠'라는 호칭", command)
        self.assertIn('"오빠라고 부르겠습니다."', profile)
        self.assertIn('"LIVE · 음성 받아쓰기"', panel)


if __name__ == '__main__':
    unittest.main()
