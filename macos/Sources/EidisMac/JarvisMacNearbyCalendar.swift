import Foundation
import MultipeerConnectivity
import CryptoKit

/// The JARVIS Mac can be paired only after the owner explicitly opens
/// the pairing panel and enters its fresh twelve-digit code on the iPhone.
/// MCSession requires encrypted peer transport; the existing HTTP API stays
/// on 127.0.0.1 and is NEVER exposed to the local network.
@MainActor
final class JarvisMacNearbyCalendar: NSObject, ObservableObject {
    static let shared = JarvisMacNearbyCalendar()
    private static let serviceType = "jarvis-cal-v1"

    @Published private(set) var code = ""
    @Published private(set) var status = "iPhone 연결 안 됨"
    @Published private(set) var connected = false
    @Published private(set) var isAdvertising = false

    private let peer = MCPeerID(displayName: "JARVIS Mac")
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var expiresAt = Date.distantPast
    private var badTries = 0
    private var authorized: Set<MCPeerID> = []
    private var clientNonces: [MCPeerID: String] = [:]
    private var serverNonces: [MCPeerID: String] = [:]

    override init() {
        super.init()
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil,
                                                 serviceType: Self.serviceType)
        advertiser.delegate = self
    }

    func startPairing() {
        advertiser.stopAdvertisingPeer()
        session.disconnect()
        authorized.removeAll()
        clientNonces.removeAll()
        serverNonces.removeAll()
        badTries = 0
        code = String(format: "%012lld", Int64.random(in: 0...999_999_999_999))
        expiresAt = Date().addingTimeInterval(600)
        connected = false
        isAdvertising = true
        status = "아이폰에서 코드를 입력해 연결하세요."
        advertiser.startAdvertisingPeer()
    }

    func stopPairing() {
        advertiser.stopAdvertisingPeer()
        isAdvertising = false
        code = ""
        if !connected { status = "iPhone 연결 안 됨" }
    }

    func disconnect() {
        session.disconnect()
        authorized.removeAll()
        clientNonces.removeAll()
        serverNonces.removeAll()
        connected = false
        stopPairing()
        status = "iPhone 연결 해제됨"
    }

    func changed() {
        guard connected else { return }
        send(["kind": "changed"], to: session.connectedPeers)
    }

    private func send(_ object: [String: Any], to peers: [MCPeerID]) {
        guard !peers.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: object),
              data.count <= 500_000 else { return }
        do {
            try session.send(data, toPeers: peers, with: .reliable)
        } catch {
            status = "아이폰 전송 실패"
        }
    }

    private func acceptProof(_ object: [String: Any], from remote: MCPeerID) {
        guard isAdvertising, Date() < expiresAt,
              session.connectedPeers.contains(remote),
              let client = clientNonces[remote], let server = serverNonces[remote],
              let clientProof = object["proof"] as? String,
              JARVISPairProof.verify(clientProof, code: code,
                  role: "phone", client: client, server: server) else {
            badTries += 1
            status = "연결 코드가 일치하지 않습니다. 다시 연결해 주세요."
            session.disconnect()
            if badTries >= 5 { stopPairing() }
            return
        }
        let macProof = JARVISPairProof.hex(code: code,
            role: "mac", client: client, server: server)
        authorized.insert(remote)
        connected = true
        send(["kind": "pairAccepted", "proof": macProof], to: [remote])
        clientNonces.removeValue(forKey: remote)
        serverNonces.removeValue(forKey: remote)
        stopPairing()
        status = "iPhone 보안 연결 완료"
    }

    private func handle(_ bytes: Data, from remote: MCPeerID) async {
        guard session.connectedPeers.contains(remote),
              bytes.count < 320_000,
              let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let kind = object["kind"] as? String else { return }
        if kind == "pairProof" {
            acceptProof(object, from: remote)
            return
        }
        guard authorized.contains(remote), kind == "sync",
              let requestID = object["requestID"] as? String,
              UUID(uuidString: requestID) != nil,
              let operations = object["operations"] as? [[String: Any]],
              operations.count <= 150 else {
            return
        }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:8765/api/calendar/sync")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["operations": operations])
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  data.count <= 480_000 else {
                throw URLError(.badServerResponse)
            }
            var payload = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            payload["kind"] = http.statusCode == 200 ? "syncResult" : "syncError"
            payload["requestID"] = requestID
            if http.statusCode != 200, payload["error"] == nil {
                payload["error"] = "일정 서버 응답 오류"
            }
            send(payload, to: [remote])
            if http.statusCode == 200 {
                await JarvisMacCalendarStore.shared.refresh()
                status = "iPhone 일정 확인 완료"
            }
        } catch {
            send(["kind": "syncError", "requestID": requestID,
                  "error": "맥 캘린더 서버를 확인할 수 없어요."], to: [remote])
            status = "맥 일정 서버 응답 없음"
        }
    }
}

extension JarvisMacNearbyCalendar: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                 didReceiveInvitationFromPeer peerID: MCPeerID,
                                 withContext context: Data?,
                                 invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // Invitation contains only a random nonce, NEVER the PIN.
            let nonce = context.flatMap { String(data: $0, encoding: .utf8) }
            let allowed = isAdvertising && Date() < expiresAt && badTries < 5 &&
                nonce.flatMap(UUID.init(uuidString:)) != nil &&
                clientNonces.isEmpty && !connected
            if allowed, let nonce {
                clientNonces[peerID] = nonce
                status = "보안 코드 검증 중"
            } else {
                badTries += 1
                if badTries >= 5 { stopPairing() }
            }
            invitationHandler(allowed, allowed ? session : nil)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                 didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            isAdvertising = false
            status = "근처 기기 검색을 시작하지 못했어요."
        }
    }
}

extension JarvisMacNearbyCalendar: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID,
                              didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                guard let client = clientNonces[peerID], isAdvertising else {
                    if !authorized.contains(peerID) { session.disconnect() }
                    return
                }
                let server = UUID().uuidString
                serverNonces[peerID] = server
                send(["kind": "pairChallenge", "clientNonce": client,
                      "serverNonce": server], to: [peerID])
                status = "iPhone 보안 확인 중"
            case .notConnected:
                connected = false
                authorized.remove(peerID)
                clientNonces.removeValue(forKey: peerID)
                serverNonces.removeValue(forKey: peerID)
                if isAdvertising { status = "아이폰에서 연결 코드를 입력해 주세요." }
                else { status = "iPhone 연결 해제됨" }
            case .connecting:
                status = "iPhone 연결 중"
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data,
                              fromPeer peerID: MCPeerID) {
        Task { @MainActor in await handle(data, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                              withName streamName: String, fromPeer peerID: MCPeerID) { }
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                              fromPeer peerID: MCPeerID, with progress: Progress) { }
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                              fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) { }
}


// Shared proof format for Mac and iPhone builds (compiled separately).
// PIN is never transmitted over the invitation context or peer session.
private enum JARVISPairProof {
    private static func message(_ role: String, _ client: String, _ server: String) -> Data {
        Data("\(role)|\(client)|\(server)".utf8)
    }
    static func hex(code: String, role: String, client: String, server: String) -> String {
        let key = SymmetricKey(data: Data(code.utf8))
        let digest = HMAC<SHA256>.authenticationCode(for: message(role, client, server), using: key)
        return Data(digest).map { String(format: "%02x", $0) }.joined()
    }
    static func verify(_ hex: String, code: String, role: String, client: String, server: String) -> Bool {
        let utf8 = Array(hex.utf8)
        guard utf8.count == 64 else { return false }
        func nibble(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: return byte - 48
            case 97...102: return byte - 87
            default: return nil
            }
        }
        var digest = Data()
        for index in stride(from: 0, to: 64, by: 2) {
            guard let h = nibble(utf8[index]), let l = nibble(utf8[index + 1]) else { return false }
            digest.append((h << 4) | l)
        }
        return HMAC<SHA256>.isValidAuthenticationCode(digest,
            authenticating: message(role, client, server),
            using: SymmetricKey(data: Data(code.utf8)))
    }
}
