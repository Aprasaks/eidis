from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
MAC=(ROOT/"macos/Sources/EidisMac/JarvisMacNearbyCalendar.swift").read_text()
PHONE=(ROOT/"ios/JARVIS/Sources/JARVISMobileNearbyCalendar.swift").read_text()

class RememberedPeerTests(unittest.TestCase):
    def test_shared_crypto(self):
        marker="private enum JARVISPairProof"
        self.assertEqual(MAC.split(marker,1)[1], PHONE.split(marker,1)[1])
        for source in (MAC,PHONE):
            for token in ("Curve25519.KeyAgreement", "hkdfDerivedSymmetricKey", "outputByteCount: 32", "SecItemCopyMatching", "SecItemDelete", "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"):
                self.assertIn(token,source)
    def test_startup_and_revoke(self):
        self.assertIn("JarvisMacNearbyCalendar.shared.startRememberedConnection()", (ROOT/"macos/Sources/EidisMac/JarvisBundledServer.swift").read_text())
        self.assertIn("nearby.setForeground(phase == .active)", (ROOT/"ios/JARVIS/Sources/JARVISHomeView.swift").read_text())
        for source in (MAC,PHONE):
            self.assertIn("guard JARVISRememberedPeer.forget()",source)
    def test_auto_requires_fresh_proof(self):
        self.assertIn('role: "invite", client: candidate, server: "resume-v2"',MAC)
        self.assertIn('role: "invite", client: nonce, server: "resume-v2"',PHONE)
        self.assertLess(MAC.index("guard JARVISPairProof.verify(clientProof"),MAC.index("authorized.insert(remote)"))
        self.assertLess(PHONE.index("JARVISPairProof.verify(macProof"),PHONE.index("trustedPeer = peer"))

if __name__=="__main__": unittest.main()
