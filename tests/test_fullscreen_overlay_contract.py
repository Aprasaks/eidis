from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = (ROOT / 'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
LIFECYCLE = (ROOT / 'macos/Sources/EidisMac/JarvisBundledServer.swift').read_text()
PACKAGING = (ROOT / 'macos/scripts/package-app.sh').read_text()
ASSET = ROOT / 'macos/Resources/Art/JARVIS_Activation_Alpha_HEVC.mov'

class FullscreenOverlayContract(unittest.TestCase):
    def test_global_hotkey_is_explicit_and_can_close(self):
        for marker in ('RegisterEventHotKey', 'kVK_ANSI_J', 'cmdKey | optionKey',
                       'if panel == nil { show() } else { dismiss() }',
                       'event.keyCode == 53', 'NSEvent.removeMonitor'):
            self.assertIn(marker, OVERLAY)

    def test_actual_desktop_overlay_and_real_looping_video(self):
        for marker in ('window.level = .screenSaver', '.canJoinAllSpaces',
                       'Color.black.opacity(0.91)', 'AVPlayerLooper',
                       'JARVIS_Activation_Alpha_HEVC', 'videoGravity = .resizeAspect',
                       'window.animator().alphaValue'):
            self.assertIn(marker, OVERLAY)
        self.assertTrue(ASSET.exists() and ASSET.stat().st_size > 1_000_000)
        self.assertIn('cp "$PACKAGE/Resources/Art/JARVIS_Activation_Alpha_HEVC.mov"', PACKAGING)

    def test_no_fake_wake_and_no_automatic_fullscreen_on_normal_launch(self):
        self.assertNotIn('SFSpeechRecognizer', OVERLAY)
        self.assertIn('arguments.contains("--overlay-preview")', OVERLAY)
        self.assertIn('fullscreen.start()', LIFECYCLE)
        self.assertIn('fullscreen.stop()', LIFECYCLE)
        self.assertIn('applicationShouldHandleReopen', LIFECYCLE)
        self.assertNotIn('applicationSupport', OVERLAY)

if __name__ == '__main__':
    unittest.main()
