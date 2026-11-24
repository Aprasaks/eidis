"""Launch is quietly resident; the old work dashboard is on-demand only."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / 'macos/Sources/EidisMac/EidisMacApp.swift').read_text()
LIFE = (ROOT / 'macos/Sources/EidisMac/JarvisBundledServer.swift').read_text()
OVERLAY = (ROOT / 'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
PLIST = (ROOT / 'macos/Resources/Info.plist').read_text()

class SummonOnlyLaunchTests(unittest.TestCase):
    def test_no_legacy_window_created_on_launch(self):
        self.assertIn('.defaultLaunchBehavior(.suppressed)', APP)
        self.assertIn('MenuBarExtra("DECHIVE"', APP)
        self.assertIn('openWindow(id: "jarvis-tools")', APP)
        self.assertIn('Button("작업 및 설정 열기")', APP)
        self.assertIn('Button("DECHIVE 소환 / 닫기', APP)
        self.assertIn('if !flag { fullscreen.show() }', LIFE)
        self.assertNotIn('NSApp.windows.first(where: { $0.title.contains("JARVIS") })?.makeKeyAndOrderFront(nil)', LIFE)

    def test_preserve_manual_summon_without_auto_microphone(self):
        self.assertIn('RegisterEventHotKey', OVERLAY)
        self.assertIn('cmdKey | optionKey', OVERLAY)
        self.assertIn('event.keyCode == 53', OVERLAY)
        self.assertNotIn('SFSpeechRecognizer', OVERLAY)
        self.assertIn('<string>3.14.16</string>', PLIST)
        self.assertIn('<string>90</string>', PLIST)
        self.assertIn('<string>15.0</string>', PLIST)

if __name__ == '__main__':
    unittest.main()
