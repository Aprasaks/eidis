"""Mac JARVIS casual text chat and opt-in background learning contracts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
SCREEN = (ROOT / "macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
LEARN = (ROOT / "macos/Sources/EidisMac/JarvisLearningMemory.swift").read_text()
STREAM = (ROOT / "macos/Sources/EidisMac/JarvisOllamaTextStream.swift").read_text()
DETACHED = (ROOT / "macos/Sources/EidisMac/JarvisDetachedCasualChatView.swift").read_text()


class CasualConversationContract(unittest.TestCase):
    def test_chat_has_visible_entry_and_close_controls(self):
        for marker in (
            'accessibilityIdentifier("jarvis-mini-open-chat")',
            'private func openMiniCasualChat()',
            'JarvisDetachedCasualChatView(dialogue: miniDialogue)',
            'chat.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)',
            "workspaceConversationPanel",
        ):
            self.assertIn(marker, SCREEN)
        for marker in (
            'accessibilityIdentifier("jarvis-casual-chat-close")',
            'accessibilityIdentifier("jarvis-casual-chat-learning")',
            'TextField("편하게 이야기해 주세요…", text: $typedText)',
        ):
            self.assertIn(marker, DETACHED)
        self.assertNotIn('accessibilityIdentifier("jarvis-casual-chat-open")', SCREEN)
        self.assertIn('let workspaceActive = !commandCenter && (dialogue.socialDashboardChannel', SCREEN)
        self.assertNotIn('dialogue.casualChatMode || dialogue.socialDashboardChannel', SCREEN)

    def test_native_chat_is_detached_and_keeps_the_core_continuous(self):
        for marker in (
            'private var detachedChatPanel: JarvisOverlayPanel?',
            'private func showDetachedChat()',
            'private func closeDetachedChat()',
            'chat.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]',
            'chat.minSize = NSSize(width: 360, height: 390)',
            'onCasualChatModeChanged = { [weak self] enabled in',
            'closeDetachedChat()',
            'persistentPlayback: corePlayback',
        ):
            self.assertIn(marker, SCREEN)
        for marker in (
            'struct JarvisDetachedCasualChatView: View',
            'JarvisLearningReviewView(learning: dialogue.learning)',
            'dialogue.dialogueTurns',
            'dialogue.streamingAnswer',
            'dialogue.submitTyped(text)',
            'dialogue.setCasualChatMode(false)',
        ):
            self.assertIn(marker, DETACHED)
        self.assertIn('onCasualChatModeChanged?(enabled)', CHAT)
        self.assertNotIn('else if dialogue.casualChatMode {', SCREEN)

    def test_text_chat_is_nonexecuting_and_uses_genuine_ollama(self):
        for marker in (
            "enum JarvisCasualChatIntent",
            "case start, stop",
            "func setCasualChatMode(_ enabled: Bool)",
            "if let intent = JarvisCasualChatIntent.parse(command)",
            "else if casualChatMode {",
            "response = try await respondCasually(command, token: token)",
            'private func respondCasually(_ prompt: String, token: UUID)',
            'let profile = await personalProfile.contextForQwen()',
            'let related = await thinkingCore.context(for: prompt, mode: .contextual)',
            'conversation.suffix(8)',
            '"model": JarvisLocalModelConfiguration.selectedModel',
            'maxReplyChars: 1000',
            'if typed && casualChatMode {',
            'isSpeaking = false',
        ):
            self.assertIn(marker, CHAT)
        casual = CHAT.split("private func respondCasually(", 1)[1].split(
            "private func planAndRespond(", 1)[0]
        self.assertNotIn('"tools"', casual)
        self.assertNotIn('execute(', casual)
        self.assertNotIn('notYetConnectedResponse', casual)
        self.assertNotIn('conversation.removeAll()', casual)
        self.assertIn('return String(final.prefix(max(1, min(maxReplyChars, 1200))))', STREAM)

    def test_learning_from_casual_chat_is_opt_in_and_reviewed(self):
        for marker in (
            "await learning.observe(prompt, casualChat: fromChat)",
            "func observe(_ utterance: String, casualChat: Bool = false)",
            "if casualChat { return true }",
            "guard enabled, Self.shouldExtract(utterance, casualChat: casualChat)",
            "private var pendingSamples: [String] = []",
            "if pendingSamples.count > 8",
            "guard !Task.isCancelled else { return }",
            "pendingSamples.removeAll()",
            'api/learning/candidate',
            '"source_excerpt": String(utterance.prefix(500))',
            "let suggestion = try JSONDecoder().decode(JarvisQwenExtraction.self, from: json)",
        ):
            self.assertIn(marker, CHAT + LEARN)
        self.assertNotIn("UserDefaults.standard.set(utterance", LEARN)
        self.assertNotIn('"api.openai.com"', LEARN)
        self.assertNotIn('"api.anthropic.com"', LEARN)


if __name__ == "__main__":
    unittest.main()
