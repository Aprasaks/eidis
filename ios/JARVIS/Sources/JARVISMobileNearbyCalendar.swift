import Foundation
import MultipeerConnectivity
import CryptoKit

/// Nearby, owner-approved calendar sync. No API key, public IP or open LAN
/// listener. MCSession *requires* encryption; Mac only accepts an invitation
/// proving both peers know the fresh twelve-digit code; PIN never sent.
@MainActor
final class JARVISMobileNearbyCalendar: NSObject, ObservableObject {
    @Published private(set) var peers: [MCPeerID] = []
    @Published private(set) var connected = false
    @Published private(set) var searching = false
    @Published private(set) var syncing = false
    @Published private(set) var status = "동기화 연결 안 됨"
    @Published private(set) var lastSync: Date?

    private let localPeer = MCPeerID(displayName: "JARVIS iPhone")
    private let calendar: JARVISCalendarStore
    private var session: MCSession!
    private var browser: MCNearbyServiceBrowser!
    private var requestID: UUID?
    private var timeoutTask: Task<Void, Never>?
    private var invitedPeer: MCPeerID?
    private var pairingCode: String?
    private var clientNonce: String?
    private var serverNonce: String?
    private var trustedPeer: MCPeerID?

    init(calendar: JARVISCalendarStore) {
        self.calendar = calendar
        super.init()
        session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: "jarvis-cal-v1")
        browser.delegate = self
    }

    func startSearch() {
        peers = []
        if !searching && !connected {
            searching = true
            status = "근처 Mac 검색 중"
            browser.startBrowsingForPeers()
        }
    }

    func stopSearch() {
        browser.stopBrowsingForPeers()
        searching = false
    }

    func invite(_ peer: MCPeerID, code: String) {
        let pin = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pin.count == 12 && pin.allSatisfy(\.isNumber), peers.contains(peer) else {
            status = "맥에 표시된 숫자 12자리를 입력해 주세요."
            return
        }
        invitedPeer = peer
        pairingCode = pin
        let nonce = UUID().uuidString
        clientNonce = nonce
        serverNonce = nil
        status = "Mac 보안 확인 중"
        // Do NOT send the PIN. Only an unpredictable nonce goes in context.
        browser.invitePeer(peer, to: session, withContext: Data(nonce.utf8), timeout: 25)
    }

    func disconnect() {
        timeoutTask?.cancel()
        requestID = nil
        syncing = false
        calendar.setSyncing(false)
        trustedPeer = nil
        pairingCode = nil
        clientNonce = nil
        serverNonce = nil
        invitedPeer = nil
        session.disconnect()
        connected = false
        stopSearch()
        status = "연결 해제됨"
    }

    func sync() {
        guard connected, !syncing, let trustedPeer,
              session.connectedPeers.contains(trustedPeer) else { return }
        let operations: [[String: Any]]
        do {
            operations = try calendar.outgoingOperations()
        } catch {
            status = error.localizedDescription
            return
        }
        let id = UUID()
        let object: [String: Any] = [
            "kind": "sync", "requestID": id.uuidString,
            "operations": operations
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard data.count < 320_000 else {
                status = "동기화할 일정이 많아요. 일부만 보내도록 조정해야 해요."
                return
            }
            calendar.setSyncing(true)
            syncing = true
            requestID = id
            status = "일정 확인 중"
            try session.send(data, toPeers: [trustedPeer], with: .reliable)
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.finishSync()
                self.status = "Mac 응답 지연 · 아이폰 일정은 그대로 보관 중"
            }
        } catch {
            finishSync()
            status = "동기화 전송 실패 · 아이폰 일정은 그대로 보관 중"
        }
    }

    private func sendPairProof(_ proof: String, to peer: MCPeerID) {
        guard session.connectedPeers.contains(peer),
              let data = try? JSONSerialization.data(withJSONObject: [
                "kind": "pairProof", "proof": proof
              ]) else { return }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            status = "Mac 보안 확인 실패"
            disconnect()
        }
    }

    private func finishSync() {
        timeoutTask?.cancel()
        timeoutTask = nil
        requestID = nil
        syncing = false
        calendar.setSyncing(false)
    }

    private func receive(_ data: Data, from peer: MCPeerID) {
        guard session.connectedPeers.contains(peer),
              data.count <= 500_000,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let kind = object["kind"] as? String else { return }

        if kind == "pairChallenge" {
            guard invitedPeer == peer,
                  let client = clientNonce, let pin = pairingCode,
                  object["clientNonce"] as? String == client,
                  let server = object["serverNonce"] as? String,
                  UUID(uuidString: server) != nil else { return }
            serverNonce = server
            let proof = JARVISPairProof.hex(code: pin, role: "phone",
                                            client: client, server: server)
            sendPairProof(proof, to: peer)
            return
        }
        if kind == "pairAccepted" {
            guard invitedPeer == peer,
                  let client = clientNonce, let server = serverNonce,
                  let pin = pairingCode,
                  let macProof = object["proof"] as? String,
                  JARVISPairProof.verify(macProof, code: pin,
                      role: "mac", client: client, server: server) else {
                status = "맥 신원 검증 실패 · 일정을 전송하지 않았어요."
                disconnect()
                return
            }
            trustedPeer = peer
            connected = true
            pairingCode = nil
            clientNonce = nil
            serverNonce = nil
            invitedPeer = nil
            status = "Mac 연결됨"
            sync()
            return
        }
        guard connected, trustedPeer == peer else { return }
        if kind == "changed" {
            if !syncing { sync() }
            return
        }
        guard let replyID = object["requestID"] as? String,
              let requestID, replyID.lowercased() == requestID.uuidString.lowercased() else {
            return
        }
        defer { finishSync() }
        if kind == "syncError" {
            status = object["error"] as? String ?? "동기화 오류"
            return
        }
        guard kind == "syncResult" else { return }
        do {
            let result = try calendar.acceptSync(object)
            lastSync = Date()
            status = result.conflicts > 0
                ? "변경 충돌 \(result.conflicts)건 · 아이폰 원본 보존"
                : "일정 동기화 완료"
        } catch {
            status = "병합 실패 · 아이폰 일정 보존: \(error.localizedDescription)"
        }
    }
}

extension JARVISMobileNearbyCalendar: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard !peers.contains(peerID) else { return }
            peers.append(peerID)
            peers.sort { $0.displayName < $1.displayName }
            status = "연결할 Mac을 선택해 주세요."
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            peers.removeAll { $0 == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            searching = false
            status = "기기 검색을 시작하지 못했어요. 로컬 네트워크 권한을 확인해 주세요."
        }
    }
}

extension JARVISMobileNearbyCalendar: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID,
                              didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                // Encrypted transport alone does not prove Mac identity.
                // Wait for BOTH HMAC proofs before any calendar transfer.
                stopSearch()
                status = "Mac 보안 확인 중"
            case .notConnected:
                connected = false
                trustedPeer = nil
                pairingCode = nil
                clientNonce = nil
                serverNonce = nil
                invitedPeer = nil
                finishSync()
                status = "연결이 끊겼어요 · 아이폰 일정 보관 중"
            case .connecting:
                status = "Mac 연결 중"
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data,
                              fromPeer peerID: MCPeerID) {
        Task { @MainActor in receive(data, from: peerID) }
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
