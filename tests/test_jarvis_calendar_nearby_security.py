"""No nearby calendar data before mutual authentication; Mac HTTP stays local."""
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]
MAC = (ROOT/'macos/Sources/EidisMac/JarvisMacNearbyCalendar.swift').read_text()
PHONE = (ROOT/'ios/JARVIS/Sources/JARVISMobileNearbyCalendar.swift').read_text()
PYTHON = (ROOT/'jarvis/server.py').read_text()

class NearbyCalendarSecurityContracts(unittest.TestCase):
    def test_multipeer_encrypted_and_bonjour_optin(self):
        for source in (MAC, PHONE):
            self.assertIn('encryptionPreference: .required', source)
            self.assertIn('jarvis-cal-v1', source)
            self.assertIn('JARVISPairProof.verify(', source)
            self.assertIn('JARVISPairProof.hex(', source)
            self.assertIn('import CryptoKit', source)
        macplist = plistlib.loads((ROOT/'macos/Resources/Info.plist').read_bytes())
        iosplist = plistlib.loads((ROOT/'ios/JARVIS/Info.plist').read_bytes())
        self.assertIn('_jarvis-cal-v1._tcp', macplist['NSBonjourServices'])
        self.assertIn('_jarvis-cal-v1._tcp', iosplist['NSBonjourServices'])
        self.assertTrue(macplist['NSLocalNetworkUsageDescription'])
        self.assertTrue(iosplist['NSLocalNetworkUsageDescription'])

    def test_iphone_does_not_send_pin_in_invitation(self):
        self.assertIn('withContext: Data(nonce.utf8)', PHONE)
        self.assertNotIn('withContext: Data(pin.utf8)', PHONE)
        self.assertIn('guard connected, trustedPeer == peer', PHONE)
        self.assertIn('JARVISPairProof.verify(macProof', PHONE)
        self.assertIn('trustedPeer = peer', PHONE)
        self.assertIn('guard authorized.contains(remote), kind == "sync"', MAC)
        self.assertIn('JARVISPairProof.verify(clientProof', MAC)
        self.assertIn('authorized.insert(remote)', MAC)
        self.assertIn('String(format: "%012lld"', MAC)

    def test_only_calendar_data_on_mac_loopback(self):
        self.assertIn('if host not in ("127.0.0.1", "localhost")', PYTHON)
        self.assertIn('"/api/calendar/sync"', PYTHON)
        self.assertIn('http://127.0.0.1:8765/api/calendar/sync', MAC)
        self.assertNotIn('http://192.', MAC)
        self.assertNotIn('https://api.elevenlabs.io', MAC)

    def test_phone_keeps_own_calendar_and_minimal_ui(self):
        store = (ROOT/'ios/JARVIS/Sources/JARVISCalendarStore.swift').read_text()
        self.assertIn('pendingIDs', store)
        self.assertIn('remoteVersions', store)
        self.assertIn('conflictCount', store)
        self.assertIn('guard !isSyncing else', store)
        screen = (ROOT/'ios/JARVIS/Sources/JARVISHomeView.swift').read_text()
        self.assertNotIn('PERSONAL AI COMPANION', screen)
        self.assertNotIn('QUICK ACTIONS', screen)
        self.assertIn('안녕하세요 오라버니!', screen)
        self.assertIn('DECHIVE_Core_Mobile', screen)

if __name__ == '__main__':
    unittest.main()
