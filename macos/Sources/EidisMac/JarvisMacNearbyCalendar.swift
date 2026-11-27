import Foundation
import MultipeerConnectivity
import CryptoKit
import Security
import Network

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
    @Published private(set) var remembered = false
    private var savedSecret: String?
    private var autoAdvertising = false
    private var pendingResume: Set<MCPeerID> = []
    private var pairingKeys: [MCPeerID: Curve25519.KeyAgreement.PrivateKey] = [:]
    private var badTries = 0
    private var publishInFlight = false
    private var authorized: Set<MCPeerID> = []
    private var clientNonces: [MCPeerID: String] = [:]
    private var serverNonces: [MCPeerID: String] = [:]

    private func makeProjectSnapshot(_ id: String) -> [String: Any] {
        let root = JarvisKnowledgeCatalog.root
        let catalog = try? JarvisKnowledgeCatalog.load()
        let day = JarvisKnowledgeDailyBudget.dayKey(at: Date())
        let night = root.appendingPathComponent("night-shifts").appendingPathComponent(day)
        let summary = (try? Data(contentsOf: night.appendingPathComponent("summary.json")))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        let latest = (try? Data(contentsOf: root.appendingPathComponent("latest-run.json")))
            .flatMap { try? JSONDecoder().decode(JarvisKnowledgePilotRun.self, from: $0) }
        var snapshot: [String: Any] = [
            "kind": "projectSnapshot", "requestID": id,
            "checkedAt": ISO8601DateFormatter().string(from: Date()),
            "day": day, "starts": JarvisKnowledgeDailyBudget.used(),
            "limit": JarvisKnowledgeDailyBudget.limit
        ]
        snapshot["dailyStagedCount"] = Set(JarvisKnowledgeDailyBudget.stagedToday()).count
        if JarvisKnowledgeDailyBudget.usesSeparateRepairs() {
            snapshot["repairStarts"] = JarvisKnowledgeDailyBudget.repairUsed()
            snapshot["repairLimit"] = JarvisKnowledgeDailyBudget.repairLimit
        }
        if let catalog { snapshot["planned"] = catalog.topics.count }
        if let summary {
            snapshot["nightReason"] = summary["reason"]
            snapshot["nightStaged"] = summary["staged"]
        }
        if let latest, let catalog,
           let topic = catalog.topics.first(where: { latest.directory.lastPathComponent.hasPrefix($0.code + "-") }) {
            snapshot["latestTitle"] = topic.title
            snapshot["latestCode"] = topic.code
            snapshot["latestState"] = latest.state.rawValue
            if latest.sanityReceipt()?.slug == topic.resolvedSlug {
                snapshot["reviewRecorded"] = true
            }
        }
        let runs = root.appendingPathComponent("runs")
        let folders = (try? FileManager.default.contentsOfDirectory(at: runs, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        var reviews: [[String: Any]] = []
        for folder in folders {
            guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("sanity-stage.json")),
                  let receipt = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let slug = receipt["slug"] as? String, let rev = receipt["rev"] as? String,
                  receipt["id"] as? String == "drafts.knowledge-" + slug,
                  receipt["status"] as? String == "review", receipt["humanVerified"] as? Bool == false,
                  let topic = catalog?.topics.first(where: { $0.resolvedSlug == slug }),
                  let article = try? String(contentsOf: folder.appendingPathComponent("article.md"), encoding: .utf8),
                  article.utf8.count < 45_000,
                  let assets = receipt["assets"] as? [String: String] else { continue }
            if let publishedData = try? Data(contentsOf: folder.appendingPathComponent("sanity-publish.json")),
               let published = (try? JSONSerialization.jsonObject(with: publishedData)) as? [String: Any],
               published["slug"] as? String == slug,
               published["approvedRevision"] as? String == rev { continue }
            reviews.append(["slug":slug, "rev":rev, "title":topic.title, "article":article,
                            "topicNumber":topic.number, "topicCode":topic.code,
                            "assets":assets, "checkedAt":receipt["checkedAt"] as? String ?? ""])
        }
        // Retain the newest receipt per topic, then send the earliest unpublished
        // local candidates first. Public state is checked again by the phone/CMS.
        var seen = Set<String>()
        let ordered = reviews.sorted {
            let a = $0["topicNumber"] as? Int ?? Int.max
            let b = $1["topicNumber"] as? Int ?? Int.max
            if a != b { return a < b }
            return ($0["checkedAt"] as? String ?? "") > ($1["checkedAt"] as? String ?? "")
        }.filter {
            guard let slug = $0["slug"] as? String else { return false }
            return seen.insert(slug).inserted
        }
        snapshot["reviews"] = Array(ordered.prefix(6))
        return snapshot
    }

    private var remoteListener: NWListener?
    private var remoteConnections: [UUID: NWConnection] = [:]
    private var remoteAuthenticated: Set<UUID> = []
    private var recentRemoteRequests: [String: Date] = [:]
    private var remoteRetry: Task<Void, Never>?

    func startRemoteProjects() {
        guard remoteRetry == nil else { return }
        remoteRetry = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.remoteListener == nil, self.remembered { self.openRemoteProjects() }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stopRemoteProjects() {
        remoteRetry?.cancel()
        remoteRetry = nil
        remoteListener?.cancel()
        remoteListener = nil
        for c in remoteConnections.values { c.cancel() }
        remoteConnections.removeAll()
        remoteAuthenticated.removeAll()
        recentRemoteRequests.removeAll()
    }

    private func openRemoteProjects() {
        guard let mac = JARVISRemoteWire.mac, JARVISRemoteWire.phone != nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(mac), port: JARVISRemoteWire.port)
        guard let listener = try? NWListener(using: params) else { return }
        remoteListener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, let listener, self.remoteListener === listener else { return }
                if case .failed = state { listener.cancel(); self.remoteListener = nil }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.remembered, self.remoteConnections.count < 8,
                      case let .hostPort(host, _) = connection.endpoint,
                      let phone = JARVISRemoteWire.phone, String(describing: host) == phone else { connection.cancel(); return }
                self.handleRemoteConnection(connection)
            }
        }
        listener.start(queue: .main)
    }

    private func handleRemoteConnection(_ connection: NWConnection) {
        let token = UUID()
        remoteConnections[token] = connection
        connection.start(queue: .main)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !self.remoteAuthenticated.contains(token) else { return }
            self.remoteConnections.removeValue(forKey: token)?.cancel()
        }
        JARVISRemoteWire.read(connection) { [weak self] data in
            Task { @MainActor in
                guard let self, self.remoteConnections[token] != nil,
                      let data, let secret = JARVISRememberedPeer.load(),
                      let clear = try? JARVISRemoteWire.decode(data, secret: secret, response: false),
                      let request = (try? JSONSerialization.jsonObject(with: clear)) as? [String: Any],
                      let kind = request["kind"] as? String,
                      // 기존 Knowledge 허용 목록은 그대로 두고, SNS 두 종류만 별도 목록으로 추가한다
                      // (JarvisSocialRemote.remoteKinds · 같은 기기 인증·암호화를 그대로 사용).
                      (["projectSnapshotRequest", "publishKnowledge"].contains(kind)
                       || JarvisSocialRemote.remoteKinds.contains(kind)),
                      let id = request["requestID"] as? String, UUID(uuidString: id) != nil,
                      let sent = request["sentAt"] as? Double, abs(Date().timeIntervalSince1970 - sent) <= 60
                else { self?.remoteConnections.removeValue(forKey: token)?.cancel(); return }
                let now = Date()
                self.recentRemoteRequests = self.recentRemoteRequests.filter { now.timeIntervalSince($0.value) < 125 }
                guard self.recentRemoteRequests[id] == nil, self.recentRemoteRequests.count < 256 else {
                    self.remoteConnections.removeValue(forKey: token)?.cancel(); return
                }
                self.recentRemoteRequests[id] = now
                self.remoteAuthenticated.insert(token)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(120))
                    guard let self else { return }
                    self.remoteAuthenticated.remove(token)
                    self.remoteConnections.removeValue(forKey: token)?.cancel()
                }
                let response: [String: Any]
                if kind == "publishKnowledge" {
                    // Only authenticated owner requests reach the same revision-bound publisher.
                    response = await self.publishApproved(request, id: id)
                } else if kind == "socialSnapshotRequest" {
                    // SNS: 채널 수치 + 검토 대기 캐러셀 미리보기 (토큰·원본 파일 없음).
                    response = await JarvisSocialRemote.snapshot(requestID: id)
                } else if kind == "approveSocialPost" {
                    // SNS: 아이폰에서 본 버전(digest)과 같을 때만 승인/반려를 기록. 게시는 하지 않는다.
                    response = JarvisSocialRemote.decide(request, requestID: id)
                } else if kind == "registerPushToken" {
                    // SNS: 잠금화면 알림용 아이폰 기기 토큰 등록 (같은 인증 통로)
                    response = JarvisSocialRemote.registerPush(request, requestID: id)
                } else if kind == JarvisPlanRemote.requestKind {
                    // 기억 탭: 프로젝트 기획서 (읽기 전용)
                    response = JarvisPlanRemote.docs(requestID: id)
                } else {
                    response = self.makeProjectSnapshot(id)
                }
                self.remoteAuthenticated.remove(token)
                guard self.remoteConnections[token] != nil,
                      let current = JARVISRememberedPeer.load(), current == secret,
                      let frame = try? JARVISRemoteWire.encode(response, secret: secret, response: true) else {
                    self.remoteConnections.removeValue(forKey: token)?.cancel(); return
                }
                connection.send(content: frame, completion: .contentProcessed { _ in
                    Task { @MainActor in self.remoteConnections.removeValue(forKey: token)?.cancel() }
                })
            }
        }
    }

    override init() {
        super.init()
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil,
                                                 serviceType: Self.serviceType)
        advertiser.delegate = self
    }

    func startRememberedConnection() {
        savedSecret = JARVISRememberedPeer.load()
        remembered = savedSecret != nil
        guard remembered, !connected, !isAdvertising, !autoAdvertising else { return }
        autoAdvertising = true
        status = "등록된 iPhone 연결 대기"
        advertiser.startAdvertisingPeer()
    }

    func startPairing() {
        guard !remembered else { return }
        autoAdvertising = false
        pendingResume.removeAll()
        pairingKeys.removeAll()
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
        guard JARVISRememberedPeer.forget() else {
            status = "기기 등록 삭제 실패 · 키체인을 확인하세요."
            return
        }
        stopRemoteProjects()
        savedSecret = nil
        remembered = false
        autoAdvertising = false
        pendingResume.removeAll()
        pairingKeys.removeAll()
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
        send(["kind": "changed"], to: session.connectedPeers.filter { authorized.contains($0) })
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
        let resuming = pendingResume.contains(remote)
        guard session.connectedPeers.contains(remote),
              let client = clientNonces[remote], let server = serverNonces[remote],
              let clientProof = object["proof"] as? String else { session.disconnect(); return }
        let secret: String
        let boundClient: String
        let boundServer: String
        var nextSecret: String?
        if resuming {
            guard let savedSecret else { session.disconnect(); return }
            secret = savedSecret
            boundClient = client
            boundServer = server
        } else {
            guard isAdvertising, Date() < expiresAt,
                  let key = pairingKeys[remote],
                  let phoneKey = object["phoneKey"] as? String,
                  let derived = JARVISRememberedPeer.derive(privateKey: key, remote: phoneKey, client: client, server: server)
            else { session.disconnect(); return }
            secret = code
            boundClient = client + "|" + phoneKey
            boundServer = server + "|" + key.publicKey.rawRepresentation.base64EncodedString()
            nextSecret = derived
        }
        guard JARVISPairProof.verify(clientProof, code: secret,
                                    role: "phone", client: boundClient, server: boundServer) else {
            if !resuming { badTries += 1 }
            status = "기기 인증 실패"
            session.disconnect()
            if !resuming && badTries >= 5 { stopPairing() }
            return
        }
        if let nextSecret {
            guard JARVISRememberedPeer.save(nextSecret) else {
                status = "기기 등록 저장 실패"
                session.disconnect()
                return
            }
            savedSecret = nextSecret
            remembered = true
            startRemoteProjects()
        }
        let macProof = JARVISPairProof.hex(code: secret,
            role: "mac", client: boundClient, server: boundServer)
        authorized.insert(remote)
        connected = true
        send(["kind": "pairAccepted", "proof": macProof], to: [remote])
        clientNonces.removeValue(forKey: remote)
        serverNonces.removeValue(forKey: remote)
        pairingKeys.removeValue(forKey: remote)
        pendingResume.remove(remote)
        stopPairing()
        autoAdvertising = false
        status = "iPhone 보안 연결 완료"
    }

    private func publishApproved(_ object: [String: Any], id: String) async -> [String: Any] {
        func reply(_ state: String) -> [String: Any] {
            ["kind":"publishResult","requestID":id,"status":state]
        }
        guard let slug = object["slug"] as? String,
              let rev = object["rev"] as? String,
              slug.count <= 96,
              slug.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil,
              rev.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil,
              object["ownerApproved"] as? Bool == true else { return reply("invalidApproval") }
        guard !publishInFlight else { return reply("busy") }
        publishInFlight = true
        defer { publishInFlight = false }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let site = home.appendingPathComponent("Documents/ChatGPT/Dechive Site")
        let process = Process()
        process.executableURL = home.appendingPathComponent(".nvm/versions/node/v24.7.0/bin/node")
        process.currentDirectoryURL = site
        process.arguments = [site.appendingPathComponent("node_modules/.bin/sanity").path,
                             "exec", site.appendingPathComponent("scripts/jarvis-knowledge-publish-approved.mjs").path,
                             "--with-user-token", "--", "--mode", "publish", "--slug", slug, "--rev", rev]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let result: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            do { try process.run() }
            catch { process.terminationHandler = nil; continuation.resume(returning: -1) }
        }
        let state = result == 0 ? "siteConfirmed" : result == 3 ? "cmsConfirmed" : result == 4 ? "outOfOrder" : "unconfirmed"
        return reply(state)
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
        // Project requests require the existing owner-proven encrypted session.
        guard authorized.contains(remote) else { return }
        if kind == "publishKnowledge" {
            guard let id = object["requestID"] as? String, UUID(uuidString: id) != nil else { return }
            let response = await publishApproved(object, id: id)
            if authorized.contains(remote) { send(response, to: [remote]) }
            return
        }
        if kind == "projectSnapshotRequest" {
            guard let id = object["requestID"] as? String, UUID(uuidString: id) != nil else { return }
            send(makeProjectSnapshot(id), to: [remote])
            return
        }
        // SNS (근거리 연결): 원격 통로와 같은 JarvisSocialRemote 처리를 사용한다.
        if kind == "socialSnapshotRequest" {
            guard let id = object["requestID"] as? String, UUID(uuidString: id) != nil else { return }
            let response = await JarvisSocialRemote.snapshot(requestID: id)
            if authorized.contains(remote) { send(response, to: [remote]) }
            return
        }
        if kind == "approveSocialPost" {
            guard let id = object["requestID"] as? String, UUID(uuidString: id) != nil else { return }
            send(JarvisSocialRemote.decide(object, requestID: id), to: [remote])
            return
        }
        if kind == "registerPushToken" {
            guard let id = object["requestID"] as? String, UUID(uuidString: id) != nil else { return }
            send(JarvisSocialRemote.registerPush(object, requestID: id), to: [remote])
            return
        }
        if kind == JarvisPlanRemote.requestKind {
            guard let id = object["requestID"] as? String, UUID(uuidString: id) != nil else { return }
            if authorized.contains(remote) { send(JarvisPlanRemote.docs(requestID: id), to: [remote]) }
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
            var acceptedNonce: String?
            if autoAdvertising, let secret = savedSecret, let context, context.count < 1024,
               let obj = (try? JSONSerialization.jsonObject(with: context)) as? [String: String],
               let candidate = obj["nonce"], UUID(uuidString: candidate) != nil,
               let proof = obj["proof"], JARVISPairProof.verify(proof, code: secret,
                   role: "invite", client: candidate, server: "resume-v2"),
               clientNonces.isEmpty, !connected {
                acceptedNonce = candidate
                pendingResume.insert(peerID)
            } else if isAdvertising && Date() < expiresAt && badTries < 5 &&
                      nonce.flatMap(UUID.init(uuidString:)) != nil && clientNonces.isEmpty && !connected {
                acceptedNonce = nonce
            }
            let allowed = acceptedNonce != nil
            if let acceptedNonce {
                clientNonces[peerID] = acceptedNonce
                status = "기기 보안 검증 중"
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard let self, self.clientNonces[peerID] == acceptedNonce else { return }
                    self.clientNonces.removeValue(forKey: peerID)
                    self.serverNonces.removeValue(forKey: peerID)
                    self.pendingResume.remove(peerID)
                    self.pairingKeys.removeValue(forKey: peerID)
                    if !self.connected { self.session.disconnect() }
                }
            }
            invitationHandler(allowed, allowed ? session : nil)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                 didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            isAdvertising = false
            autoAdvertising = false
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
                guard let client = clientNonces[peerID], isAdvertising || pendingResume.contains(peerID) else {
                    if !authorized.contains(peerID) { session.disconnect() }
                    return
                }
                let server = UUID().uuidString
                serverNonces[peerID] = server
                var challenge = ["kind": "pairChallenge", "clientNonce": client, "serverNonce": server]
                if pendingResume.contains(peerID) {
                    challenge["mode"] = "resume"
                } else {
                    let key = Curve25519.KeyAgreement.PrivateKey()
                    pairingKeys[peerID] = key
                    challenge["mode"] = "register"
                    challenge["macKey"] = key.publicKey.rawRepresentation.base64EncodedString()
                }
                send(challenge, to: [peerID])
                status = "iPhone 보안 확인 중"
            case .notConnected:
                connected = false
                authorized.remove(peerID)
                clientNonces.removeValue(forKey: peerID)
                serverNonces.removeValue(forKey: peerID)
                pendingResume.remove(peerID)
                pairingKeys.removeValue(forKey: peerID)
                if remembered && !isAdvertising {
                    startRememberedConnection()
                } else if isAdvertising { status = "아이폰에서 연결 코드를 입력해 주세요." }
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

/// One remembered peer per installation. Key material never goes into defaults,
/// discovery info, logs or the invitation. A fresh proof is required each time.
private enum JARVISRememberedPeer {
    static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.dechive.jarvis.nearby.v2",
        kSecAttrAccount as String: "owner-pairing"
    ]
    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data, data.count == 32 else { return nil }
        return data.base64EncodedString()
    }
    static func save(_ secret: String) -> Bool {
        guard let data = Data(base64Encoded: secret), data.count == 32 else { return false }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }
    static func forget() -> Bool {
        let result = SecItemDelete(query as CFDictionary)
        return result == errSecSuccess || result == errSecItemNotFound
    }
    static func derive(privateKey: Curve25519.KeyAgreement.PrivateKey, remote: String,
                       client: String, server: String) -> String? {
        guard let bytes = Data(base64Encoded: remote),
              let publicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes),
              let shared = try? privateKey.sharedSecretFromKeyAgreement(with: publicKey) else { return nil }
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self,
            salt: Data((client + "|" + server).utf8),
            sharedInfo: Data("JARVIS remembered peer v2".utf8), outputByteCount: 32)
        return key.withUnsafeBytes { Data($0).base64EncodedString() }
    }
}

private enum JARVISRemoteWire {
    static let mac = configuredAddress("JARVISRemoteMac")
    static let phone = configuredAddress("JARVISRemotePhone")
    private static func configuredAddress(_ key: String) -> String? {
        guard let address = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { UInt8($0) }
        guard parts.count == 4, numbers.count == 4, numbers[0] == 100,
              (64...127).contains(numbers[1]),
              numbers.map({ String($0) }).joined(separator: ".") == address else { return nil }
        return address
    }
    static let port = NWEndpoint.Port(rawValue: 48765)!
    static let maxBytes = 500_000
    static func key(_ secret: String, response: Bool) throws -> SymmetricKey {
        guard let bytes = Data(base64Encoded: secret), bytes.count == 32 else { throw URLError(.userAuthenticationRequired) }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes),
            salt: Data("JARVIS remote projects v1".utf8),
            info: Data((response ? "mac-response" : "phone-request").utf8), outputByteCount: 32)
    }
    static func encode(_ object: [String: Any], secret: String, response: Bool) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: object)
        let box = try AES.GCM.seal(data, using: key(secret, response: response))
        guard let sealed = box.combined, sealed.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
        var n = UInt32(sealed.count).bigEndian
        return Data(bytes: &n, count: 4) + sealed
    }
    static func decode(_ data: Data, secret: String, response: Bool) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key(secret, response: response))
    }
    static func read(_ c: NWConnection, completion: @escaping (Data?) -> Void) {
        c.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
            guard error == nil, let header, header.count == 4 else { completion(nil); return }
            let count = header.reduce(0) { ($0 << 8) | Int($1) }
            guard count >= 28, count <= maxBytes else { completion(nil); return }
            c.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                guard error == nil, let data, data.count == count else { completion(nil); return }
                completion(data)
            }
        }
    }
}
