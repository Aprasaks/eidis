import sys
"""Source contracts and real CryptoKit round trip for authenticated remote projects."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
MAC = (ROOT / "macos/Sources/EidisMac/JarvisMacNearbyCalendar.swift").read_text()
PHONE = (ROOT / "ios/JARVIS/Sources/JARVISMobileNearbyCalendar.swift").read_text()
VIEW = (ROOT / "ios/JARVIS/Sources/JARVISMobileDashboardView.swift").read_text()

class RemoteProjectContracts(unittest.TestCase):
    def test_remote_is_allowlisted_and_owner_scoped(self):
        listener = MAC.split("private func openRemoteProjects()")[1].split("override init()")[0]
        self.assertIn("params.requiredLocalEndpoint", listener)
        self.assertIn("JARVISRemoteWire.phone", listener)
        self.assertIn("JARVISRememberedPeer.load()", listener)
        self.assertIn('["projectSnapshotRequest", "publishKnowledge"].contains(kind)', listener)
        self.assertIn("recentRemoteRequests[id] == nil", listener)
        self.assertIn("<= 60", listener)
        self.assertIn("self.makeProjectSnapshot(id)", listener)
        self.assertIn("await self.publishApproved(request, id: id)", listener)
        self.assertNotIn("Process()", listener)
        self.assertIn(".disabled(!nearby.canPublish || !isFirstReview(review))", VIEW)
        self.assertIn('Button("공개 발행 승인")', VIEW)
        self.assertIn('confirmationDialog("실제 사이트에 공개하시겠습니까?"', VIEW)
        publisher = MAC.split("private func publishApproved(")[1].split("private func handle(")[0]
        self.assertIn('object["ownerApproved"] as? Bool == true', publisher)
        self.assertIn('guard !publishInFlight', publisher)
        self.assertIn('defer { publishInFlight = false }', publisher)
        self.assertIn('"--mode", "publish", "--slug", slug, "--rev", rev', publisher)
        self.assertIn("await publishApproved(object, id: id)", MAC)
        self.assertIn("projectSnapshot?.reviews?.contains", PHONE)
        self.assertIn('reply["requestID"] as? String == id', PHONE)
        self.assertIn("자동 재전송 없음", PHONE)
    def test_keys_and_protocol_agree(self):
        wire = MAC.split("private enum JARVISRemoteWire {")[1]
        self.assertEqual(wire, PHONE.split("private enum JARVISRemoteWire {")[1])
        self.assertIn("AES.GCM.seal", wire)
        self.assertIn("AES.GCM.open", wire)
        self.assertIn("HKDF<SHA256>", wire)
        self.assertIn("stopRemoteProjects()", MAC)
        self.assertIn("stopRemoteRead()", PHONE)
        self.assertIn('object["requestID"] as? String == id', PHONE)
        self.assertIn("!self.connected, self.remembered", PHONE)
    @unittest.skipUnless(shutil.which("swift") and sys.platform == "darwin", "macOS Swift (Darwin/CryptoKit) required")
    def test_real_cryptokit(self):
        wire = MAC.split("private enum JARVISRemoteWire {")[1]
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"test.swift"
            p.write_text("import Foundation\nimport CryptoKit\nimport Network\nprivate enum JARVISRemoteWire {"+wire+"""
let k = Data(repeating: 73, count: 32).base64EncodedString()
let bad = Data(repeating: 74, count: 32).base64EncodedString()
let request = ["kind":"projectSnapshotRequest","requestID":UUID().uuidString]
let frame = try JARVISRemoteWire.encode(request, secret:k, response:false)
let data = Data(frame.dropFirst(4))
let clear = try JARVISRemoteWire.decode(data, secret:k, response:false)
precondition((try! JSONSerialization.jsonObject(with:clear) as! [String:String]) == request)
precondition((try? JARVISRemoteWire.decode(data,secret:bad,response:false)) == nil)
precondition((try? JARVISRemoteWire.decode(data,secret:k,response:true)) == nil)
var altered = data
altered[altered.count-1] ^= 1
precondition((try? JARVISRemoteWire.decode(altered,secret:k,response:false)) == nil)
let second = try JARVISRemoteWire.encode(request,secret:k,response:false)
precondition(frame != second)
let reply = try JARVISRemoteWire.encode(request,secret:k,response:true)
let answer = try JARVISRemoteWire.decode(Data(reply.dropFirst(4)),secret:k,response:true)
precondition(!answer.isEmpty)
""")
            subprocess.run(["swift",str(p)],check=True,timeout=45)

if __name__ == "__main__":
    unittest.main()
