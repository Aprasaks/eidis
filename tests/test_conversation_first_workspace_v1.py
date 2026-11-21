"""Conversation-first workspace, fast turn-taking and keyboard-focus regression."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
OVERLAY=(ROOT/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
CONVERSATION=(ROOT/"macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
BROWSER=(ROOT/"macos/Sources/EidisMac/JarvisOverlayBrowser.swift").read_text()
POLICY=(ROOT/"macos/Sources/EidisMac/JarvisVoiceShortcutPolicy.swift").read_text()

class ConversationFirstTests(unittest.TestCase):
    def test_faster_silence_completion_and_old_default_migrated(self):
        self.assertIn("migratedPause = 1.8",CONVERSATION)
        self.assertIn("jarvis.dialogue.fastPauseV1",CONVERSATION)
        self.assertIn("abs(savedPause - 6.5) >= 0.01",CONVERSATION)
        self.assertIn("min(max(silenceWaitSeconds, 1.2), 8.0)",CONVERSATION)
        self.assertIn(">= self.silenceWaitSeconds",CONVERSATION)
        self.assertIn("String(partial.prefix(6000)) != self.liveTranscript",CONVERSATION)
        self.assertIn("self.listener.finish()",CONVERSATION)
        for option in ('Button("빠르게 · 1.8초")',
                       'Button("보통 · 2.8초")',
                       'Button("천천히 · 4.0초")',
                       'Button("수동 종료 · Space")',
                       'accessibilityIdentifier("jarvis-voice-silence-control")'):
            self.assertIn(option,OVERLAY)

    def test_work_mode_has_separate_left_composer_and_right_web_view(self):
        self.assertIn("let workspaceActive = !commandCenter",OVERLAY)
        self.assertIn("let conversationWidth = min(max(area.size.width * 0.30, 255), 470)",OVERLAY)
        self.assertIn("HStack(spacing: 16) {",OVERLAY)
        self.assertIn("workspaceConversationPanel",OVERLAY)
        self.assertIn(".frame(width: conversationWidth)",OVERLAY)
        self.assertIn("embeddedBrowserPanel(url: url)",OVERLAY)
        self.assertIn("if !workspaceActive {",OVERLAY)
        self.assertIn("&& !workspaceActive {",OVERLAY)
        self.assertIn('accessibilityIdentifier("jarvis-workspace-text-input")',OVERLAY)
        self.assertIn('accessibilityIdentifier("jarvis-workspace-send")',OVERLAY)
        self.assertIn('accessibilityIdentifier("jarvis-workspace-microphone")',OVERLAY)
        self.assertIn('ForEach(dialogue.dialogueTurns)',OVERLAY)
        self.assertIn('Text(dialogue.liveTranscript.isEmpty ?',OVERLAY)
        self.assertNotIn(".frame(width: min(790, max(510, area.size.width * 0.29))",OVERLAY)
        self.assertIn("JarvisLoopingCore(videoURL: videoURL, compact: compactCore)",OVERLAY)

    def test_global_opt_space_only_installed_with_overlay(self):
        self.assertIn('RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey)',OVERLAY)
        self.assertIn("case 53: key.onMicrophone?()",OVERLAY)
        self.assertIn("hotkey?.installMicrophone()",OVERLAY)
        self.assertIn("hotkey?.uninstallMicrophone()",OVERLAY)
        self.assertIn("JarvisVoiceShortcutPolicy.handles(",OVERLAY)
        self.assertIn("event.window?.firstResponder is NSTextView",OVERLAY)
        self.assertIn("self.dialogue?.browser.isEditingWebText == true",OVERLAY)
        self.assertIn("isRepeat: event.isARepeat",OVERLAY)
        self.assertIn("if relevant == [.option] { return true }",POLICY)
        self.assertIn("!composerEditing && !browserEditing",POLICY)

    def test_web_content_bridges_boolean_focus_only(self):
        self.assertIn("WKScriptMessageHandler",BROWSER)
        self.assertIn('name: "dechiveInputFocus"',BROWSER)
        self.assertIn("let focused = message.body as? Bool",BROWSER)
        self.assertIn("browser.updateWebTextEditing(focused, in: view)",BROWSER)
        self.assertIn("forMainFrameOnly: true",BROWSER)
        self.assertIn("removeScriptMessageHandler(",BROWSER)
        self.assertIn('configuration.websiteDataStore = .nonPersistent()',BROWSER)
        self.assertNotIn('document.cookie',BROWSER)
        self.assertNotIn('localStorage',BROWSER)
        self.assertNotIn('document.activeElement.value',BROWSER)

if __name__=="__main__":
    unittest.main()
