from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = (ROOT/'macos/scripts/package-app.sh').read_text()
ELEVEN = (ROOT/'macos/Sources/EidisMac/ElevenLabsVoiceService.swift').read_text()
INFO = (ROOT/'macos/Resources/Info.plist').read_text()

class StableKeychainSigning(unittest.TestCase):
    def test_packaging_has_durable_signing_identity_not_adhoc(self):
        self.assertNotIn('codesign --force --sign - "$APP"', PACKAGE)
        for needle in ('security find-identity -v -p codesigning',
                       'JARVIS_SIGNING_IDENTITY',
                       'SIGNING_IDENTITY="$MATCHES"',
                       '/usr/bin/codesign --force --sign "$SIGNING_IDENTITY"',
                       'codesign --verify --deep --strict',
                       'anchor apple generic',
                       'exit 2'):
            self.assertIn(needle, PACKAGE)
        self.assertIn('<string>3.14.3</string>', INFO)
    def test_key_never_moved_to_insecure_settings_or_files(self):
        for needle in ('kSecClassGenericPassword',
                       'dev.dechive.eidis.elevenlabs',
                       'kSecAttrAccessibleWhenUnlockedThisDeviceOnly',
                       'SecItemCopyMatching(query as CFDictionary',
                       'kSecAttrService as String: service'):
            self.assertIn(needle, ELEVEN)
        self.assertNotIn('defaults.set(key,', ELEVEN)
        self.assertNotIn('FileHandle(forWritingTo:', ELEVEN)

if __name__ == '__main__': unittest.main()
