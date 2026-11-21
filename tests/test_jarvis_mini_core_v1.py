"""Mini core 2: explicit microphone, stable placement and workspace promotion."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
OVERLAY=(ROOT/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
SHELL=(ROOT/"macos/Sources/EidisMac/EidisMacApp.swift").read_text()
CHAT=(ROOT/"macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()

class MiniCoreTests(unittest.TestCase):
    def test_opt_in_and_s_shortcut(self):
        for value in ('UserDefaults.standard.bool(forKey: "jarvis.mini.enabled")',
                      'UserDefaults.standard.set(miniEnabled, forKey: "jarvis.mini.enabled")',
                      'if miniEnabled { showMini() }',
                      'RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | optionKey)',
                      'case 54: key.onMini?()', 'key.installMini()', 'UnregisterEventHotKey(miniHotkey)'):
            self.assertIn(value,OVERLAY)
        self.assertIn('작은 코어 숨기기  ⌘⌥S',SHELL)
        self.assertIn('fullscreen.toggleMini()',SHELL)
        self.assertIn('RegisterEventHotKey(UInt32(kVK_ANSI_J)',OVERLAY)

    def test_round_core_size_and_placement(self):
        for value in ('private struct JarvisMiniCoreView: View',
                      'JarvisLoopingCore(videoURL: videoURL, compact: true)',
                      '.clipShape(Circle())', 'mini.level = .floating',
                      'mini.backgroundColor = .clear', 'mini.hidesOnDeactivate = false',
                      '.canJoinAllSpaces, .fullScreenAuxiliary', 'screen.visibleFrame',
                      'jarvis.mini.diameter', 'jarvis.mini.frame',
                      'NSWindow.didMoveNotification','window?.performDrag(with: event)',
                      'Self.clampMini(proposed,visible:visible)',
                      'min(max(miniDiameter+amount,160),340)',
                      'accessibilityIdentifier("jarvis-mini-expand")',
                      'accessibilityIdentifier("jarvis-mini-hide")'):
            self.assertIn(value,OVERLAY)

    def test_explicit_single_turn_and_caption(self):
        section=OVERLAY[OVERLAY.index("private struct JarvisMiniCoreView: View"):
                        OVERLAY.index("private struct JarvisSummonedView: View")]
        self.assertIn('Button(action: microphone)',section)
        self.assertIn('if !caption.isEmpty',section)
        self.assertIn('dialogue.streamingAnswer',section)
        self.assertNotIn('activateListening()',section)
        self.assertNotIn('SFSpeech',section)
        self.assertIn('voice.miniSingleTurn = true',OVERLAY)
        self.assertIn('voice.prepareMiniStandby()',OVERLAY)
        self.assertIn('miniDialogue.toggleMicrophone()',OVERLAY)
        self.assertIn('if miniSingleTurn {',CHAT)
        self.assertIn('finishMiniTurn()',CHAT)
        self.assertIn('elapsed >= 30 && self.listener.transcript.isEmpty',CHAT)
        self.assertIn('elapsed >= 120',CHAT)
        self.assertIn('if isActive { activateListening() }',CHAT)

    def test_promote_preserves_same_conversation_and_releases_player(self):
        self.assertIn('voice.onWorkspaceRequested = { [weak self] in self?.promoteMini() }',OVERLAY)
        self.assertIn('present(fullscreenDialogue: voice)',OVERLAY)
        self.assertIn('hideMini(preserveDialogue: fullscreenDialogue != nil)',OVERLAY)
        self.assertIn('let dialogue = fullscreenDialogue ?? JarvisOverlayConversation()',OVERLAY)
        self.assertIn('dialogue.miniSingleTurn = false',OVERLAY)
        self.assertIn('miniPanel.contentView = nil',OVERLAY)
        self.assertIn('if !preserveDialogue {',OVERLAY)
        self.assertIn('miniDialogue?.cancel()',OVERLAY)
        self.assertGreaterEqual(CHAT.count('onWorkspaceRequested?()'),6)
        self.assertIn('func stop() {\n        hideMini()',OVERLAY)

if __name__=="__main__":unittest.main()
