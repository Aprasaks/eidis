from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'macos' / 'Sources' / 'EidisMac'
CHROME = (SRC / 'JarvisChromeSession.swift').read_text()
DIALOGUE = (SRC / 'JarvisOverlayConversation.swift').read_text()
UI = (SRC / 'JarvisCommandCenterView.swift').read_text()
# The SNS / YouTube channel monitor moved to its own file; check both.
UI += "\n" + (SRC / 'JarvisChannelMonitorView.swift').read_text()
OVERLAY = (SRC / 'JarvisFullscreenOverlay.swift').read_text()
BRIDGE = (ROOT / 'tools/chrome-bridge/check.mjs').read_text()
POLICY = (ROOT / 'tools/chrome-bridge/policy.mjs').read_text()
PACKAGE = (ROOT / 'macos/scripts/package-app.sh').read_text()

class ChromeBridgeSafetyTests(unittest.TestCase):
    def test_existing_chrome_selected_without_session_extraction(self):
        self.assertIn('com.google.Chrome', CHROME)
        self.assertIn('NSWorkspace.shared.open([url], withApplicationAt: chrome', CHROME)
        self.assertIn('return url.absoluteString == exact.absoluteString', CHROME)
        self.assertNotIn('CookieStore', CHROME)
        self.assertNotIn('Keychain', CHROME)
        self.assertIn('await onChromeWorkspaceOpen?(channel, channelID)', DIALOGUE)
        self.assertIn('await dialogue.chrome.openWorkspace(channel', OVERLAY)
        self.assertNotIn('dialogue.onChromeOpened', OVERLAY)
        self.assertIn('window.setFrame(sidebar', OVERLAY)
        self.assertIn('window.level = .floating', OVERLAY)
        self.assertIn('set bounds of workWindow to wantedBounds', CHROME)
        self.assertIn('set workWindow to make new window', CHROME)
        self.assertIn('workspaceWindowID = id', CHROME)
    def test_chrome_access_requires_direct_ui_action_and_user_approval(self):
        self.assertIn('jarvis-meta-chrome-check', UI)
        self.assertIn('Task { await dialogue.verifyChromeSession() }', UI)
        self.assertIn('--autoConnect', BRIDGE)
        self.assertIn('chrome_remote_debugging_or_permission_needed', BRIDGE)
        self.assertIn('list_pages', BRIDGE)
        self.assertIn('onChromeVerificationBegin', OVERLAY)
        self.assertIn('panel.level = .screenSaver', OVERLAY)
        self.assertNotIn('get_cookies', BRIDGE)
        self.assertNotIn('take_screenshot', BRIDGE)
        self.assertNotIn('evaluate_script', BRIDGE)
        self.assertIn('--no-javascript-evaluation', BRIDGE)
        self.assertIn('--no-usage-statistics', BRIDGE)
    def test_only_approved_dechive_channel_metadata_is_reported(self):
        self.assertIn('summarizePages(result)', BRIDGE)
        self.assertIn('allowed.find', POLICY)
        for platform in ('instagram','facebook','threads','youtube'):
            self.assertIn("['"+platform+"'", POLICY)
        self.assertIn('tools/chrome-bridge', PACKAGE)
        self.assertNotIn('User Data', PACKAGE)
