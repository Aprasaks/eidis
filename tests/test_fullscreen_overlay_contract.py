from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = (ROOT / 'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
LIFECYCLE = (ROOT / 'macos/Sources/EidisMac/JarvisBundledServer.swift').read_text()
PACKAGING = (ROOT / 'macos/scripts/package-app.sh').read_text()
ASSET = ROOT / 'macos/Resources/Art/DECHIVE_FullHD_Loop.mp4'

class FullscreenOverlayContract(unittest.TestCase):
    def test_global_hotkey_is_explicit_and_can_close(self):
        for marker in ('RegisterEventHotKey', 'kVK_ANSI_J', 'cmdKey | optionKey',
                       'if panel == nil { show() }', 'else { dismiss() }', 'dialogue?.chromeWorkspaceVisible == true',
                       'event.keyCode == 53', 'NSEvent.removeMonitor'):
            self.assertIn(marker, OVERLAY)

    def test_actual_desktop_overlay_and_real_looping_video(self):
        for marker in ('window.level = .screenSaver', 'window.hidesOnDeactivate = false', '.canJoinAllSpaces',
                       'Color.black.opacity(appeared ? 1 : 0)', 'AVPlayerLooper',
                       'DECHIVE_FullHD_Loop', 'videoGravity = compact ? .resizeAspectFill : .resizeAspect',
                       'window.orderOut(nil)', 'window.contentView = nil'):
            self.assertIn(marker, OVERLAY)
        self.assertTrue(ASSET.exists() and ASSET.stat().st_size > 1_000_000)
        self.assertIn('cp "$PACKAGE/Resources/Art/DECHIVE_FullHD_Loop.mp4"', PACKAGING)
        self.assertNotIn('Bundle.main.url(forResource: "JARVIS_Activation_Alpha_HEVC"', OVERLAY)
        self.assertGreater(ASSET.stat().st_size, 3_500_000)
        self.assertIn('rm -f "$RESOURCES/JARVIS_Activation_Alpha_HEVC.mov"', PACKAGING)

    def test_fullscreen_video_player_outlives_chat_view_updates(self):
        # The 10-second source film must not restart when chat opens or
        # streamed replies trigger SwiftUI body updates.
        for marker in (
            'final class JarvisVideoPlayback',
            'let corePlayback: JarvisVideoPlayback',
            'persistentPlayback: corePlayback',
            'let corePlayback = JarvisVideoPlayback(url: url)',
            'if !coordinator.persistent { coordinator.playback.player.pause() }',
        ):
            self.assertIn(marker, OVERLAY)
        # Keep the existing fullscreen movie unchanged.
        self.assertIn('AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))', OVERLAY)

    def test_esc_is_immediate_and_screen_switching_has_input_guards(self):
        self.assertIn('else { self.dismiss() }\n                    return nil', OVERLAY)
        self.assertIn('hotkey?.uninstallEscape()', OVERLAY)
        self.assertIn('await dialogue.returnFromChromeWorkspace()', OVERLAY)
        self.assertIn('window.orderOut(nil)', OVERLAY)
        self.assertIn('window.contentView = nil', OVERLAY)
        self.assertNotIn('window.animator().alphaValue = 0', OVERLAY)
        for marker in ('DragGesture(minimumDistance: 80)',
                       'moveToAdjacentScreen(value.translation.width < 0 ? 1 : -1)',
                       'NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel])',
                       'handleHorizontalScroll',
                       'abs(horizontalScrollTotal) > 80',
                       'NSScreen.screens.sorted',
                       'screens.indices.contains(next)',
                       'panel.setFrame(screens[next].frame, display: true, animate: false)',
                       'event.keyCode == 123 || event.keyCode == 124'):
            self.assertIn(marker, OVERLAY)

    def test_no_fake_wake_and_no_automatic_fullscreen_on_normal_launch(self):
        self.assertNotIn('SFSpeechRecognizer', OVERLAY)
        self.assertIn('arguments.contains("--overlay-preview")', OVERLAY)
        self.assertIn('fullscreen.start()', LIFECYCLE)
        self.assertIn('fullscreen.stop()', LIFECYCLE)
        self.assertIn('applicationShouldHandleReopen', LIFECYCLE)
        self.assertNotIn('applicationSupport', OVERLAY)

if __name__ == '__main__':
    unittest.main()
