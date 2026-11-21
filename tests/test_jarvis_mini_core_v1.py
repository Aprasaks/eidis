"""Opt-in mini JARVIS core and nonintrusive desktop mode contracts."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
OVERLAY=(ROOT/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
SHELL=(ROOT/"macos/Sources/EidisMac/EidisMacApp.swift").read_text()

class MiniCoreTests(unittest.TestCase):
    def test_mini_is_opt_in_and_persists_user_choice(self):
        self.assertIn('UserDefaults.standard.bool(forKey: "jarvis.mini.enabled")',OVERLAY)
        self.assertIn('UserDefaults.standard.set(miniEnabled, forKey: "jarvis.mini.enabled")',OVERLAY)
        self.assertIn('if miniEnabled { showMini() }',OVERLAY)
        self.assertIn('fullscreen.miniEnabled ? "작은 코어 숨기기" : "작은 코어 항상 띄우기"',SHELL)
        self.assertIn('fullscreen.toggleMini()',SHELL)

    def test_non_obstructive_small_window_uses_existing_core_asset(self):
        self.assertIn("private struct JarvisMiniCoreView: View",OVERLAY)
        self.assertIn("JarvisLoopingCore(videoURL: videoURL, compact: true)",OVERLAY)
        self.assertIn("width: 230, height: 245",OVERLAY)
        self.assertIn("mini.level = .floating",OVERLAY)
        self.assertIn("mini.hidesOnDeactivate = false",OVERLAY)
        self.assertIn(".canJoinAllSpaces, .fullScreenAuxiliary",OVERLAY)
        self.assertIn("screen.visibleFrame",OVERLAY)
        self.assertIn("mini.isMovableByWindowBackground = true",OVERLAY)
        self.assertIn('accessibilityIdentifier("jarvis-mini-expand")',OVERLAY)
        self.assertIn('accessibilityIdentifier("jarvis-mini-hide")',OVERLAY)

    def test_only_one_video_panel_and_no_mic_in_mini(self):
        start=OVERLAY.index("private struct JarvisMiniCoreView: View")
        end=OVERLAY.index("private struct JarvisSummonedView: View")
        mini=OVERLAY[start:end]
        self.assertNotIn("activateListening",mini)
        self.assertNotIn("toggleMicrophone",mini)
        self.assertNotIn("SFSpeech",mini)
        self.assertNotIn("JarvisOverlayConversation()",mini)
        self.assertIn("hideMini()",OVERLAY)
        self.assertIn("if miniEnabled { showMini() }",OVERLAY)
        self.assertIn("miniPanel.contentView = nil",OVERLAY)
        self.assertIn("hideMini()",OVERLAY)
        self.assertIn("private func handleMicrophoneShortcut()",OVERLAY)
        self.assertIn("private var panel: JarvisOverlayPanel?",OVERLAY)

if __name__=="__main__":
    unittest.main()
