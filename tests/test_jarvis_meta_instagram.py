"""Static invariants for the native, read-only DECHIVE.WIKI Meta integration."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
META = (ROOT / "macos/Sources/EidisMac/JarvisMetaInstagramService.swift").read_text()
DASH = (ROOT / "macos/Sources/EidisMac/JarvisLiveDashboard.swift").read_text()
UI = (ROOT / "macos/Sources/EidisMac/JarvisCommandCenterView.swift").read_text()


class MetaInstagramSecurityContract(unittest.TestCase):
    def test_only_pinned_wiki_account_is_accepted(self):
        for expected in (
            'accountID = "17841447171659454"',
            'accountName = "dechive.wiki"',
            'profile.id == accountID',
            'profile.username?.lowercased() == accountName',
        ):
            self.assertIn(expected, META)

    def test_read_only_graph_api_request_without_url_token(self):
        self.assertIn('https://graph.facebook.com/v27.0/', META)
        self.assertIn('request.httpMethod = "GET"', META)
        self.assertIn('"Bearer " + token', META)
        self.assertNotIn('?access_token=', META)
        self.assertNotIn('request.httpMethod = "POST"', META)
        self.assertNotIn('request.httpMethod = "DELETE"', META)
        self.assertNotIn('graph.instagram.com', META)

    def test_keychain_persistence_and_verification_first(self):
        for text in ('SecItemCopyMatching(', 'SecItemUpdate(', 'SecItemAdd(',
                     'kSecAttrAccessibleWhenUnlockedThisDeviceOnly',
                     'guard checked.connected else', 'saveVerifiedToken(token)'):
            self.assertIn(text, META + DASH)
        self.assertNotIn('UserDefaults.standard.set', META)
        self.assertNotIn('print(token)', META + DASH + UI)

    def test_user_direct_token_submission_is_masked(self):
        for expected in ('SecureField("Meta 액세스 토큰"',
                         'jarvis-instagram-token-secure-field',
                         'instagramTokenInput = ""',
                         '.onDisappear { instagramTokenInput = "" }',
                         'jarvis-instagram-token-connect',
                         '.sheet(isPresented: $showInstagramTokenSheet)'):
            self.assertIn(expected, UI)
        self.assertIn('startInstagramScanIfNeeded(id: id)', DASH)
        self.assertIn('timeIntervalSince($0) > 300', DASH)


if __name__ == "__main__":
    unittest.main()
