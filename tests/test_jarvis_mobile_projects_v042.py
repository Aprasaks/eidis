import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAC = (ROOT / "macos/Sources/EidisMac/JarvisMacNearbyCalendar.swift").read_text()
PHONE = (ROOT / "ios/JARVIS/Sources/JARVISMobileNearbyCalendar.swift").read_text()
VIEW = (ROOT / "ios/JARVIS/Sources/JARVISMobileDashboardView.swift").read_text()

class MobileProjectContracts(unittest.TestCase):
    def test_owner_proof_before_snapshot(self):
        self.assertLess(MAC.index("guard authorized.contains(remote) else"), MAC.index('if kind == "projectSnapshotRequest"'))
        self.assertLess(PHONE.index("guard connected, trustedPeer == peer else"), PHONE.index('if kind == "projectSnapshot"'))
        self.assertIn('object["requestID"] as? String == id', PHONE)

    def test_public_is_not_review(self):
        self.assertIn('status=="published" && humanVerified==true', VIEW)
        self.assertIn("검토 등록 기록 있음 · 공개 발행과 별개", VIEW)
        self.assertIn("APNs 연결 전", VIEW)

    def test_snapshot_no_private_artifacts(self):
        block = MAC.split('private func makeProjectSnapshot(')[1].split('private var remoteListener')[0]
        for forbidden in ['snapshot["directory"]', 'snapshot["token"]', 'snapshot["article"]']:
            self.assertNotIn(forbidden, block)
        self.assertIn("return snapshot", block)
        self.assertIn("send(makeProjectSnapshot(id), to: [remote])", MAC)

if __name__ == "__main__":
    unittest.main()
