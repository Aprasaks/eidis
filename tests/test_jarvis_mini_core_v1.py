"""Mini core 3: core-only surface, opt-in wake standby and detached everyday chat."""
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
                      'mini.isMovableByWindowBackground = true',
                      '.canJoinAllSpaces, .fullScreenAuxiliary', 'screen.visibleFrame',
                      'jarvis.mini.diameter', 'jarvis.mini.frame',
                      'NSWindow.didMoveNotification',
                      'Self.clampMini(proposed,visible:visible)',
                      'accessibilityIdentifier("jarvis-mini-open-chat")',
                      'dragCore: { [weak self] delta in self?.dragMiniCore(by: delta)',
                      'DragGesture(minimumDistance: 9)'):
            self.assertIn(value,OVERLAY)
        core=OVERLAY.split("private struct JarvisMiniCoreView: View", 1)[1].split(
            "private struct JarvisSummonedView: View", 1)[0]
        for forbidden in ('minus.circle','plus.circle','mic.circle',
                          'xmark.circle','jarvis-mini-hide','jarvis-mini-expand'):
            self.assertNotIn(forbidden,core)

    def test_wake_opens_nearby_chat_without_fullscreen(self):
        for value in ('UserDefaults.standard.set(true, forKey: dekaPreferenceKey)',
                      'startPreferredDeka()', 'private func openMiniCasualChat()',
                      'miniDialogue.setCasualChatMode(true)',
                      'self.openMiniCasualChat()',
                      'voice.beginDekaWakeTurn()',
                      'JarvisDetachedCasualChatView(dialogue: miniDialogue)',
                      'private func closeDetachedChat()',
                      'miniDialogue?.onCasualChatModeChanged = nil',
                      'voice.onCasualChatModeChanged = { [weak self] enabled in',
                      'chat.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)'):
            self.assertIn(value, OVERLAY)
        self.assertIn('voice.miniSingleTurn = true',OVERLAY)
        self.assertIn('voice.prepareMiniStandby()',OVERLAY)
        self.assertIn('if singleTurnCapture {',CHAT)
        self.assertIn('miniSingleTurn || wakeTurn || (wakeStandbyEnabled && !dashboardDictationEnabled)',CHAT)
        self.assertIn('finishMiniTurn()',CHAT)
        self.assertIn('elapsed >= 30 && self.listener.transcript.isEmpty',CHAT)
        self.assertIn('elapsed >= 120',CHAT)
        self.assertIn('if dashboardDictationEnabled || isActive { activateListening() }',CHAT)

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
        self.assertIn('func stop() {\n        closeDetachedChat()\n        dialogue?.onCasualChatModeChanged = nil\n        stopDeka()\n        hideMini()',OVERLAY)

if __name__=="__main__":unittest.main()
