"""HOME standby UI is core-only; physical monitors have stable roles."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SWIFT = ROOT / "macos" / "Sources" / "EidisMac"
OVERLAY = (SWIFT / "JarvisFullscreenOverlay.swift").read_text()
CHAT = (SWIFT / "JarvisOverlayConversation.swift").read_text()
ROLES = (SWIFT / "JarvisDisplayRoles.swift").read_text()


class HomeStandbyDisplayRolesContract(unittest.TestCase):
    def test_home_is_visual_core_only_not_chat_or_composer(self):
        body = OVERLAY.split("    private var standardBody: some View {", 1)[1].split(
            "    private var restingControls: some View {", 1
        )[0]
        self.assertIn("JarvisLoopingCore(videoURL: videoURL, compact: compactCore,", body)
        self.assertIn("persistentPlayback: corePlayback", body)
        self.assertIn("LinearGradient(stops: [", body)
        self.assertIn(".init(color: .white, location: 0.765)", body)
        self.assertIn(".init(color: .clear, location: 0.815)", body)
        self.assertNotIn("restingControls", body)
        self.assertNotIn("JarvisLiveDialoguePanel(dialogue: dialogue, quiet: true)", body)
        self.assertIn("if workspaceActive {", body)
        self.assertIn("if commandCenter {", body)
        self.assertIn("} else if workspaceActive {", body)

    def test_home_is_silent_and_does_not_take_keyboard(self):
        present = OVERLAY.split("private func present(fullscreenDialogue:", 1)[1].split(
            "private func openMiniCasualChat()", 1
        )[0]
        self.assertIn("dialogue.prepareHomeStandby()", present)
        self.assertIn("window.orderFrontRegardless()", present)
        self.assertNotIn("window.makeKey()", present)
        self.assertNotIn("NSApp.activate(ignoringOtherApps: true)", present)
        self.assertNotIn("hotkey?.installEscape()", present)
        self.assertNotIn("speakSummonGreeting(", present)
        self.assertIn("func prepareHomeStandby()", CHAT)
        self.assertIn('status = wakeStandbyEnabled ? "호출 대기 · Jarvis"', CHAT)
        self.assertIn("voice.beginDekaWakeTurn()", OVERLAY)
        self.assertIn("key.onPress = { [weak self] in self?.toggle() }", OVERLAY)

    def test_three_actual_displays_mapped_without_changing_mac_layout(self):
        self.assertIn("enum JarvisDisplayRoles", ROLES)
        self.assertIn("case home, work, secondary", ROLES)
        self.assertIn("CGDisplayIsBuiltin(", ROLES)
        self.assertIn('"LG FULL HD"', ROLES)
        self.assertIn('"TFG30F20W"', ROLES)
        self.assertIn("UserDefaults.standard.set(match.localizedName", ROLES)
        self.assertIn("JarvisDisplayRoles.registerConnectedScreens()", OVERLAY)
        self.assertIn("JarvisDisplayRoles.hasHouseholdArrangement()", OVERLAY)
        self.assertIn("let screen = JarvisDisplayRoles.screen(for: .home)", OVERLAY)
        self.assertIn("!ProcessInfo.processInfo.arguments.contains(\"--dashboard-inspection\")", OVERLAY)
        self.assertNotIn("CGConfigureDisplayOrigin", ROLES)

if __name__ == "__main__":
    unittest.main()
