"""JARVIS v3.7.1 must never block UI boot on macOS Keychain unlock."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOICE = (ROOT / "macos/Sources/EidisMac/ElevenLabsVoiceService.swift").read_text()
WINDOW = (ROOT / "macos/Sources/EidisMac/EidisMacApp.swift").read_text()
PLIST = (ROOT / "macos/Resources/Info.plist").read_text()

class MacKeychainStartupTests(unittest.TestCase):
    def test_initialization_has_no_synchronous_keychain_access(self):
        start = VOICE.index("    init(defaults: UserDefaults = .standard) {")
        end = VOICE.index("    private func refreshSavedKeyAvailability() async {", start)
        init_body = VOICE[start:end]
        self.assertNotIn("Self.readKey()", init_body)
        self.assertIn("let hasSavedKey = false", init_body)
        self.assertIn("Task { [weak self] in", init_body)
        self.assertIn("await self?.refreshSavedKeyAvailability()", init_body)
        self.assertIn("Task.detached(priority: .utility)", VOICE)
        self.assertIn("guard revision == keyStateRevision else { return }", VOICE)

    def test_user_api_calls_still_require_explicit_opt_in(self):
        self.assertIn('guard (enabled || explicitlyPreviewed) && keyPresent', VOICE)
        self.assertNotIn('private static let maxRequests = 5', VOICE)
        self.assertIn('private static let maxCharacters = 600', VOICE)
        self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly', VOICE)
        self.assertIn('let key = await Task.detached(priority: .userInitiated)', VOICE)
        self.assertIn('fallback.speak(phrase)', VOICE)
        self.assertIn('SecItemDelete(', VOICE)
        self.assertIn('SecItemAdd(', VOICE)
        self.assertIn('SecItemUpdate(', VOICE)

    def test_app_remains_user_controlled_and_versioned(self):
        self.assertIn('showLaunchIntro', WINDOW)
        self.assertIn('localServer.connectOnLaunch()', WINDOW)
        self.assertRegex(PLIST, r'<string>3\.(?:7\.[1-9][0-9]*|8\.[0-9]+|9\.[0-9]+|10\.[0-9]+|11\.[0-9]+|12\.[0-9]+|13\.[0-9]+)</string>')
        self.assertRegex(PLIST, r'<string>(?:3[89]|4[0-9]|5[0-9]|6[0-9]|7[0-3])</string>')

if __name__ == '__main__':
    unittest.main()
