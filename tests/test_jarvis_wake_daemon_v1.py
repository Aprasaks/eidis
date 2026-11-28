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
        # 2026-11-28: 흰빛→금빛 생성 연출을 다시 틀고, 금빛일 때 "Welcome home, DECHIVE." 후 대시보드
        self.assertIn("dialogue?.formReplay += 1", overlay)
        self.assertIn("JarvisConversationLanguage.homeGreeting", overlay)
        lang = (MAC / "JarvisConversationLanguage.swift").read_text(encoding="utf-8")
        self.assertIn('"Welcome home, DECHIVE."', lang)
        self.assertIn("where voice?.isSpeaking == true", overlay)
        app = (MAC / "EidisMacApp.swift").read_text(encoding="utf-8")
        self.assertEqual(app.count(".handlesExternalEvents(matching: [])"), 4)


class WakeDaemonCpuAndCrashGuard(unittest.TestCase):
    """상시 듣기 CPU 절약(소리 있을 때만 모델) + 크래시 때만 자동 재실행 (2026-11-27)."""
    def test_gate_and_guard(self):
        src = (pathlib.Path(__file__).resolve().parents[1] / "tools/wakeword/jarvis_wake_daemon.py").read_text(encoding="utf-8")
        self.assertIn("PREROLL", src)               # 'Hey' 앞부분을 잃지 않게 직전 소리를 보관
        self.assertIn("model.reset()", src)
        self.assertIn('"EidisMac-*.ips"', src)      # 크래시 보고서가 새로 생겼을 때만
        self.assertIn('"-g", "-b", "dev.dechive.eidis"', src)
        self.assertIn("closed normally", src)       # 정상 종료는 존중


if __name__ == "__main__":
    unittest.main()
