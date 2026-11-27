"""잠금화면 알림 계약: 키 파일은 서명에만, 토큰은 인증 통로로만, 실제 이벤트에서만 발송."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAC = ROOT / "macos/Sources/EidisMac"


class PushContract(unittest.TestCase):
    def test_mac_sender(self):
        src = (MAC / "JarvisPushNotifier.swift").read_text(encoding="utf-8")
        self.assertIn("P256.Signing.PrivateKey(pemRepresentation: pem)", src)
        self.assertIn('"^[0-9a-f]{64,200}$"', src)
        self.assertIn("posixPermissions: 0o600", src)
        self.assertNotIn("NSLog(pem", src)
        remote = (MAC / "JarvisSocialRemote.swift").read_text(encoding="utf-8")
        self.assertIn('"registerPushToken", JarvisPlanRemote.requestKind, JarvisPhoneChat.requestKind, JarvisStockBoard.phoneRequestKind]', remote)
        for f in ("JarvisCarouselRunner.swift", "JarvisInstagramPublisher.swift", "JarvisThreadsPublisher.swift"):
            self.assertIn("JarvisPushNotifier.shared.send(", (MAC / f).read_text(encoding="utf-8"))

    def test_iphone(self):
        ios = ROOT / "ios"
        self.assertIn("aps-environment", (ios / "JARVIS/JARVIS.entitlements").read_text())
        self.assertIn("@UIApplicationDelegateAdaptor(JARVISPushAppDelegate.self)",
                      (ios / "JARVIS/Sources/JARVISApp.swift").read_text(encoding="utf-8"))
        self.assertIn('"kind": "registerPushToken"',
                      (ios / "JARVIS/Sources/JARVISMobileNearbyCalendar.swift").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
