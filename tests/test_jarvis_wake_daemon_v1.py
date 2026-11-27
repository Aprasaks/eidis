"""백그라운드 'Hey JARVIS' 호출 계약."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAC = ROOT / "macos/Sources/EidisMac"


class WakeDaemon(unittest.TestCase):
    def test_daemon_local_only(self):
        src = (ROOT / "tools/wakeword/jarvis_wake_daemon.py").read_text(encoding="utf-8")
        self.assertIn("hey_jarvis_v0.1.onnx", src)
        self.assertIn('"jarvis-mac://wake-dashboard"', src)
        self.assertIn("COOLDOWN = 10.0", src)
        self.assertNotIn("requests.", src)
        self.assertNotIn("wave.open", src)   # 소리를 파일로 저장하지 않음

    def test_app_handles_wake(self):
        plist = (ROOT / "macos/Resources/Info.plist").read_text(encoding="utf-8")
        self.assertIn("<string>jarvis-mac</string>", plist)
        server = (MAC / "JarvisBundledServer.swift").read_text(encoding="utf-8")
        self.assertIn('url.scheme == "jarvis-mac" && url.host == "wake-dashboard"', server)
        overlay = (MAC / "JarvisFullscreenOverlay.swift").read_text(encoding="utf-8")
        self.assertIn('"Opening your dashboard, DECHIVE."', overlay)
        self.assertIn("where JarvisKokoroVoice.shared.isPlaying", overlay)
        app = (MAC / "EidisMacApp.swift").read_text(encoding="utf-8")
        self.assertEqual(app.count(".handlesExternalEvents(matching: [])"), 4)


if __name__ == "__main__":
    unittest.main()
