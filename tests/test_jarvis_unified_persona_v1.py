"""Shared identity and audited action routing across JARVIS conversation windows."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "macos" / "Sources" / "EidisMac"
PERSONA = (SOURCES / "JarvisPersona.swift").read_text()
CHAT = (SOURCES / "JarvisOverlayConversation.swift").read_text()
COMMAND = (SOURCES / "JarvisCommandEngine.swift").read_text()
WINDOW = (SOURCES / "JarvisFullscreenOverlay.swift").read_text()


class UnifiedPersonaContract(unittest.TestCase):
    def test_one_persona_policy_in_both_model_paths(self):
        self.assertIn('static let preferredAddress = "DECHIVE"', PERSONA)
        self.assertIn('static let systemGuidance', PERSONA)
        self.assertIn("정확하고 간결하게", PERSONA)
        self.assertGreaterEqual(CHAT.count("JarvisPersona.systemGuidance"), 2)
        self.assertIn("'DECHIVE'(데카이브)라는 호칭", COMMAND)
        for source in SOURCES.glob("*.swift"):
            if source.name == "JarvisPersona.swift":
                continue  # Contains a deliberate prohibition of the old address.
            self.assertNotIn("오라버니", source.read_text(), source.name)

    def test_casual_chat_routes_explicit_existing_actions_without_changing_mode(self):
        self.assertIn('else if shouldRouteCasualToWorkspace(command) {', CHAT)
        self.assertIn('response = try await planAndRespond(command, token: token)', CHAT)
        self.assertIn("JarvisCasualProjectKnowledge.isInventoryQuestion(phrase)", CHAT)
        for identifier in (
            "StockBoardIntent.parse(phrase)",
            "WeatherIntent.parse(phrase)",
            "JarvisBriefingIntent.parse(phrase)",
            "JarvisMacCalendarIntent.parse(phrase)",
            "JarvisLiveDashboardIntent.parse(phrase)",
            "JarvisCommand.directFallback(for: phrase)",
            "JarvisLocalClock.parse(phrase)",
        ):
            self.assertIn(identifier, CHAT)
        self.assertIn("guard explicitAction else { return false }", CHAT)
        self.assertIn('response = try await respondCasually(command, token: token)', CHAT)

    def test_windows_share_conversation_and_learning_approval(self):
        self.assertIn("JarvisDetachedCasualChatView(dialogue: miniDialogue)", WINDOW)
        self.assertIn("JarvisLearningIntent.parse(command)", CHAT)
        self.assertIn("await learning.observe(prompt, casualChat: fromChat)", CHAT)
        self.assertIn("JarvisPersona.systemGuidance", CHAT)
        self.assertNotIn('"tools"', CHAT.split("private func respondCasually(", 1)[1].split("private func planAndRespond(", 1)[0])


if __name__ == "__main__":
    unittest.main()
