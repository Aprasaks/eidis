"""Mac-screen branding is DECHIVE; spoken name is 자비스; user address is 주인님."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT / "macos"
APP = (MAC / "Sources/EidisMac/EidisMacApp.swift").read_text()
OVERLAY = (MAC / "Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
PANEL = (MAC / "Sources/EidisMac/JarvisLiveDialoguePanel.swift").read_text()
ROOM = (MAC / "Sources/EidisMac/JarvisCommandCenterView.swift").read_text()
CHAT = (MAC / "Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
VOICE = (MAC / "Sources/EidisMac/ElevenLabsVoiceService.swift").read_text()
MODEL = (MAC / "Sources/EidisMac/JarvisCommandEngine.swift").read_text()
PROFILE = (MAC / "Sources/EidisMac/JarvisPersonalProfile.swift").read_text()
PACKAGING = (MAC / "scripts/package-app.sh").read_text()
PLIST = (MAC / "Resources/Info.plist").read_text()
WEB = (ROOT / "web/index.html").read_text()
SOURCE = MAC / "Resources/Art"

class DechiveIdentityContract(unittest.TestCase):
    def test_all_primary_mac_surface_branding_is_dechive(self):
        self.assertIn('MenuBarExtra("DECHIVE"', APP)
        self.assertIn('WindowGroup("DECHIVE"', APP)
        self.assertIn('<key>CFBundleDisplayName</key>\n\t<string>DECHIVE</string>', PLIST)
        self.assertIn('<key>CFBundleName</key>\n\t<string>DECHIVE</string>', PLIST)
        self.assertIn('<string>dev.dechive.eidis</string>', PLIST)
        self.assertIn('Text("DECHIVE / LIVE DIALOGUE")', PANEL)
        self.assertIn('Text("DECHIVE / COMMAND CENTER")', ROOM)
        self.assertIn('Text("DECHIVE CORE / ACTIVE")', ROOM)
        self.assertIn('Text("DECHIVE")', APP)

    def test_video_clip_is_new_brand_without_deleting_original(self):
        self.assertTrue((SOURCE / "JARVIS_FullHD_Loop.mp4").is_file())
        self.assertTrue((SOURCE / "DECHIVE_FullHD_Loop.mp4").is_file())
        self.assertGreater((SOURCE / "DECHIVE_FullHD_Loop.mp4").stat().st_size, 3_500_000)
        self.assertIn('url(forResource: "DECHIVE_FullHD_Loop"', OVERLAY)
        self.assertIn('cp "$PACKAGE/Resources/Art/DECHIVE_FullHD_Loop.mp4"', PACKAGING)
        self.assertIn('rm -f "$RESOURCES/JARVIS_FullHD_Loop.mp4"', PACKAGING)
        self.assertNotIn('url(forResource: "JARVIS_FullHD_Loop"', OVERLAY)

    def test_live_dialogue_is_display_only(self):
        self.assertIn('ScrollView(.vertical)', PANEL)
        self.assertIn('dialogue.liveTranscript', PANEL)
        self.assertIn('dialogue.dialogueTurns', PANEL)
        for forbidden in ('Toggle(', 'Slider(', 'Button(', 'SecureField(', 'Settings('):
            self.assertNotIn(forbidden, PANEL)
        self.assertIn('dialogue.toggleMicrophone()', OVERLAY)  # Existing bottom command control
        self.assertIn('dialogue.isSpeaking ? "끼어들기"', OVERLAY)

    def test_spoken_name_owner_address_and_existing_voice_command(self):
        self.assertIn('private static let summonGreeting = "주인님, 자비스입니다."', VOICE)
        self.assertIn("예외 없이 '주인님'이라는 호칭을 사용하세요", MODEL)
        self.assertIn("사용자는 당신을 '자비스'라고 부릅니다", MODEL)
        self.assertIn('s.hasPrefix("자비스")', PROFILE)
        self.assertIn('"주인님이라고 부르겠습니다."', PROFILE)
        self.assertIn('filter { $0 != "display_name" }', PROFILE)
        self.assertIn('JarvisLiveDialogueTurn(role: "DECHIVE"', CHAT)
        self.assertIn('DECHIVE / DESIGN LABORATORY', WEB)

if __name__ == "__main__":
    unittest.main()
