import Foundation
import MultipeerConnectivity
import CryptoKit
import Security
import Network
import WidgetKit

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
    @Published private(set) var remembered = false
    private var savedSecret: String?
    private var resuming = false
    private var foreground = false
    private var retryTask: Task<Void, Never>?
    private var handshakeTask: Task<Void, Never>?
    private var boundClient: String?
    private var boundServer: String?
    private var nextSecret: String?


    private var remoteConnection: NWConnection?
    @Published private(set) var remoteProjectVerified = false
    @Published private(set) var remoteOnly = false
    @Published private(set) var remoteStatus = "원격 조회 전"

    var connectionSummary: String {
        if connected { return "근거리 보안 연결 · 일정·발행 가능" }
        if remoteProjectVerified { return "Tailscale 원격 연결 · 조회 및 승인 발행" }
        return remembered ? "등록된 Mac 연결 확인 중" : "기기 등록 필요"
    }

    func setRemoteOnly(_ enabled: Bool) {
        guard remembered, !publishing, remoteOnly != enabled else { return }
        remoteOnly = enabled
        if enabled {
            stopSearch()
            clearHandshake()
            trustedPeer = nil
            connected = false
            finishSync()
            session.disconnect()
            projectRequestID = nil
            status = "근거리 연결 일시 중지"
        }
        stopRemoteRead()
        remoteStatus = "원격 조회 전"
        remoteLastRefresh = .distantPast
        setForeground(foreground)
        refreshProjects()
    }
    private var remoteLastRefresh = Date.distantPast

    private func stopRemoteRead() {
        remoteConnection?.cancel()
        remoteConnection = nil
        remoteProjectVerified = false
    }

    private func readRemoteProjects() {
        guard foreground, remembered, !connected, remoteConnection == nil,
              let secret = savedSecret else { return }
        guard let mac = JARVISRemoteWire.mac else { remoteStatus = "원격 주소 설정 필요"; return }
        let id = UUID().uuidString
        let request: [String: Any] = ["kind":"projectSnapshotRequest", "requestID":id,
                                      "sentAt":Date().timeIntervalSince1970]
        guard let frame = try? JARVISRemoteWire.encode(request, secret: secret, response: false) else { return }
        let c = NWConnection(host: NWEndpoint.Host(mac), port: JARVISRemoteWire.port, using: .tcp)
        remoteConnection = c
        remoteLastRefresh = Date()
        remoteStatus = "원격 인증 및 조회 중"
        if !remoteProjectVerified { projectStatus = remoteStatus }
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let c else { return }
            Task { @MainActor in
                guard let self, self.remoteConnection === c else { return }
                if case .ready = state {
                    c.stateUpdateHandler = nil
                    c.send(content: frame, completion: .contentProcessed { error in
                        guard error == nil else { c.cancel(); return }
                        JARVISRemoteWire.read(c) { data in
                            Task { @MainActor in
                                guard self.remoteConnection === c else { return }
                                defer { c.cancel(); self.remoteConnection = nil }
                                guard !self.connected, self.remembered,
                                      let data, let clear = try? JARVISRemoteWire.decode(data, secret: secret, response: true),
                                      let object = (try? JSONSerialization.jsonObject(with: clear)) as? [String: Any],
                                      object["kind"] as? String == "projectSnapshot",
                                      object["requestID"] as? String == id,
                                      let snapshot = try? JSONDecoder().decode(JARVISProjectSnapshot.self, from: clear)
                                else {
                                    self.remoteProjectVerified = false
                                    self.remoteStatus = "원격 인증 또는 조회 실패 · 마지막 확인값"
                                    self.projectStatus = self.remoteStatus
                                    return
                                }
                                self.projectSnapshot = snapshot
                                self.remoteProjectVerified = true
                                if self.invitedPeer == nil { self.stopSearch() }
                                self.remoteStatus = "Tailscale 원격 조회 완료"
                                self.projectStatus = self.remoteStatus
                            }
                        }
                    })
                } else if case .failed = state {
                    self.stopRemoteRead()
                    self.remoteStatus = "원격 Mac 응답 없음 · 마지막 확인값"
            self.projectStatus = self.remoteStatus
                }
            }
        }
        c.start(queue: .main)
        Task { [weak self, weak c] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, let c, self.remoteConnection === c else { return }
            self.stopRemoteRead()
            self.remoteStatus = "원격 Mac 응답 없음 · 마지막 확인값"
            self.projectStatus = self.remoteStatus
        }
    }

    func setForeground(_ active: Bool) {
        foreground = active
        retryTask?.cancel()
        retryTask = nil
        guard active else { stopRemoteRead(); return }
        savedSecret = JARVISRememberedPeer.load()
        remembered = savedSecret != nil
        guard remembered else { return }
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.foreground, self.remembered else { return }
                if !self.remoteOnly && !self.remoteProjectVerified && !self.connected && self.invitedPeer == nil {
                    if !self.searching { self.startSearch() }
                }
                if !self.connected && Date().timeIntervalSince(self.remoteLastRefresh) >= 10 { self.readRemoteProjects() }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func armHandshakeTimeout(_ nonce: String) {
        handshakeTask?.cancel()
        handshakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, self.clientNonce == nonce, !self.connected else { return }
            self.clearHandshake()
            self.session.disconnect()
            self.status = "기기 인증 응답 없음"
        }
    }

    private func clearHandshake() {
        handshakeTask?.cancel()
        handshakeTask = nil
        invitedPeer = nil
        pairingCode = nil
        clientNonce = nil
        serverNonce = nil
        boundClient = nil
        boundServer = nil
        nextSecret = nil
        resuming = false
    }

    private func resume(_ peer: MCPeerID) {
        guard foreground, remembered, !remoteOnly, !remoteProjectVerified, !connected, invitedPeer == nil, let secret = savedSecret else { return }
        let nonce = UUID().uuidString
        let proof = JARVISPairProof.hex(code: secret, role: "invite", client: nonce, server: "resume-v2")
        guard let context = try? JSONSerialization.data(withJSONObject: ["nonce":nonce,"proof":proof]) else { return }
        invitedPeer = peer
        pairingCode = secret
        clientNonce = nonce
        resuming = true
        armHandshakeTimeout(nonce)
        browser.invitePeer(peer, to: session, withContext: context, timeout: 25)
    }
    @Published private(set) var projectSnapshot: JARVISProjectSnapshot?
    @Published private(set) var projectStatus = "Mac 연결 전"
    private var projectRequestID: String?

    @Published private(set) var publishing = false
    @Published private(set) var publishStatus: String?
    @Published private(set) var publishRevision = 0
    private var publishRequestID: String?
    private var remotePublishConnection: NWConnection?
    var canPublish: Bool {
        remembered && (connected || remoteProjectVerified) && !publishing
    }

    private func finishPublish(_ id: String, state: String) {
        guard publishRequestID == id else { return }
        remotePublishConnection?.cancel()
        remotePublishConnection = nil
        publishRequestID = nil
        publishing = false
        switch state {
        case "siteConfirmed": publishStatus = "발행 완료 · 실제 사이트 확인"
        case "cmsConfirmed": publishStatus = "CMS 공개 완료 · 사이트 반영은 추가 확인 필요"
        case "busy": publishStatus = "다른 발행 처리 중"
        case "outOfOrder": publishStatus = "앞선 목차의 검토 원고부터 발행하세요. 공개 변경 없음."
        case "invalidApproval": publishStatus = "승인 정보가 유효하지 않음 · 원고를 다시 확인하세요."
        default: publishStatus = "발행 결과 미확인 · 공개 목록 확인 후 판단하세요. 자동 재전송 없음."
        }
        publishRevision += 1
        refreshProjects()
    }

    private func publishRemotely(_ review: JARVISReviewArticle, id: String) {
        guard let secret = savedSecret, let mac = JARVISRemoteWire.mac, remoteProjectVerified, foreground else {
            finishPublish(id, state: "unconfirmed"); return
        }
        let object: [String: Any] = ["kind":"publishKnowledge","requestID":id,
            "slug":review.slug,"rev":review.rev,"ownerApproved":true,"sentAt":Date().timeIntervalSince1970]
        guard let frame = try? JARVISRemoteWire.encode(object, secret: secret, response: false) else {
            finishPublish(id, state: "unconfirmed"); return
        }
        let c = NWConnection(host: NWEndpoint.Host(mac), port: JARVISRemoteWire.port, using: .tcp)
        remotePublishConnection = c
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let c else { return }
            Task { @MainActor in
                guard let self, self.remotePublishConnection === c, self.publishRequestID == id else { return }
                if case .ready = state {
                    c.stateUpdateHandler = nil
                    c.send(content: frame, completion: .contentProcessed { error in
                        if error != nil {
                            Task { @MainActor in self.finishPublish(id, state: "unconfirmed") }
                            return
                        }
                        JARVISRemoteWire.read(c) { data in
                            Task { @MainActor in
                                guard self.remotePublishConnection === c, self.publishRequestID == id else { return }
                                guard let data, let clear = try? JARVISRemoteWire.decode(data, secret: secret, response: true),
                                      let reply = (try? JSONSerialization.jsonObject(with: clear)) as? [String: Any],
                                      reply["kind"] as? String == "publishResult",
                                      reply["requestID"] as? String == id,
                                      let result = reply["status"] as? String else {
                                    self.finishPublish(id, state: "unconfirmed"); return
                                }
                                self.finishPublish(id, state: result)
                            }
                        }
                    })
                } else if case .failed = state {
                    self.finishPublish(id, state: "unconfirmed")
                }
            }
        }
        c.start(queue: .main)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(115))
            self?.finishPublish(id, state: "unconfirmed")
        }
    }

    func publish(_ review: JARVISReviewArticle) {
        guard canPublish, foreground,
              projectSnapshot?.reviews?.contains(where: { $0.slug == review.slug && $0.rev == review.rev }) == true else { return }
        let id = UUID().uuidString
        publishRequestID = id
        publishing = true
        publishStatus = "발행 요청 전송 중"
        if !connected {
            publishRemotely(review, id: id)
            return
        }
        guard let peer = trustedPeer, session.connectedPeers.contains(peer) else {
            finishPublish(id, state: "unconfirmed"); return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: [
                "kind":"publishKnowledge", "requestID":id, "slug":review.slug,
                "rev":review.rev, "ownerApproved":true
            ])
            try session.send(data, toPeers:[peer], with:.reliable)
            Task { [weak self] in
                try? await Task.sleep(for:.seconds(90))
                guard let self, self.publishRequestID == id else { return }
                self.publishRequestID = nil
                self.publishing = false
                self.publishStatus = "응답 없음 · 공개 목록을 새로고침해 실제 상태를 확인하세요."
                self.publishRevision += 1
            }
        } catch {
            publishRequestID = nil
            publishing = false
            publishStatus = "발행 요청 전송 실패"
        }
    }


    func refreshProjects() {
        guard connected, let peer = trustedPeer, session.connectedPeers.contains(peer) else {
            if remembered { readRemoteProjects() } else { projectStatus = "Mac 연결 전 · 마지막 확인값" }
            return
        }
        let id = UUID().uuidString
        projectRequestID = id
        projectStatus = "Mac 작업 기록 확인 중"
        do {
            let data = try JSONSerialization.data(withJSONObject: ["kind": "projectSnapshotRequest", "requestID": id])
            try session.send(data, toPeers: [peer], with: .reliable)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.projectRequestID == id else { return }
                self.projectRequestID = nil
                self.projectStatus = "Mac 프로젝트 응답 없음 · 마지막 확인값"
            }
        } catch {
            projectRequestID = nil
            projectStatus = "Mac 프로젝트 조회 실패"
        }
    }

    // MARK: - SNS (아이폰 SNS 화면) -------------------------------------------
    // Knowledge와 같은 기기 인증·암호화 통로를 그대로 쓰고, 메시지 종류만 다르다.
    //   socialSnapshotRequest → socialSnapshot        (채널 수치 + 검토 대기 캐러셀 미리보기)
    //   approveSocialPost     → socialApprovalResult  (본 버전 digest와 같을 때만 승인/반려 기록)
    // Mac 쪽 처리: macos/Sources/EidisMac/JarvisSocialRemote.swift

    @Published private(set) var socialSnapshot: JARVISSocialSnapshot?
    @Published private(set) var socialStatus = "Mac SNS 현황 확인 전"
    @Published private(set) var socialLoading = false
    @Published private(set) var socialDeciding = false
    @Published private(set) var socialDecisionStatus: String?
    /// 응답을 기다리는 요청들 (requestID → 완료 처리). 근거리 응답은 receive()에서 여기로 전달된다.
    private var macReplies: [String: (Data?) -> Void] = [:]

    func refreshSocial() {
        guard !socialLoading else { return }
        guard connected || remembered else { socialStatus = "Mac 기기 등록 필요"; return }
        let id = UUID().uuidString
        socialLoading = true
        socialStatus = "Mac SNS 현황 확인 중"
        let object: [String: Any] = ["kind": "socialSnapshotRequest", "requestID": id]
        sendToMac(object, id: id, expect: "socialSnapshot", timeout: 15) { [weak self] data in
            guard let self else { return }
            self.socialLoading = false
            guard let data, let snapshot = try? JSONDecoder().decode(JARVISSocialSnapshot.self, from: data) else {
                self.socialStatus = "Mac SNS 응답 없음 · 마지막 확인값"
                return
            }
            self.socialSnapshot = snapshot
            self.socialStatus = self.connected ? "근거리 Mac SNS 현황" : "Tailscale 원격 SNS 현황"
            // 홈·잠금화면 위젯 갱신 (App Group에 요약 저장 → 위젯 다시 그리기)
            snapshot.widgetSummary.save()
            WidgetCenter.shared.reloadAllTimelines()
            self.registerPushIfNeeded()
        }
    }

    /// 사용자가 미리보기로 본 바로 그 버전(digest)에 대한 승인/반려. 게시는 Mac에서 별도로 진행된다.
    func decideSocial(_ carousel: JARVISSocialCarousel, approve: Bool) {
        guard !socialDeciding, carousel.status == "review" else { return }
        let id = UUID().uuidString
        socialDeciding = true
        socialDecisionStatus = approve ? "승인 전송 중" : "반려 전송 중"
        let object: [String: Any] = ["kind": "approveSocialPost", "requestID": id,
                                     "runID": carousel.runID, "digest": carousel.digest,
                                     "decision": approve ? "approve" : "reject", "ownerApproved": true]
        sendToMac(object, id: id, expect: "socialApprovalResult", timeout: 20) { [weak self] data in
            guard let self else { return }
            self.socialDeciding = false
            let reply = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            switch reply?["status"] as? String {
            case "approved": self.socialDecisionStatus = "승인 완료 · Mac에 게시 대기로 기록됨"
            case "rejected": self.socialDecisionStatus = "반려 완료 · 게시하지 않음"
            case "changed": self.socialDecisionStatus = "미리보기 이후 결과물이 바뀌었어요. 새로 불러온 뒤 다시 확인하세요."
            case "notReviewable": self.socialDecisionStatus = "이미 처리된 캐러셀이에요."
            case "notFound": self.socialDecisionStatus = "Mac에서 캐러셀을 찾지 못했어요."
            case "invalid": self.socialDecisionStatus = "승인 정보가 올바르지 않아요."
            default: self.socialDecisionStatus = "응답 없음 · 새로고침해 실제 상태를 확인하세요."
            }
            self.refreshSocial()
        }
    }

    /// 잠금화면 알림용 기기 토큰을 Mac에 한 번 등록한다 (토큰이 바뀌면 다시 등록).
    func registerPushIfNeeded() {
        let defaults = UserDefaults.standard
        guard let token = defaults.string(forKey: JARVISPushAppDelegate.tokenKey),
              defaults.string(forKey: "jarvis.push.registeredToken") != token else { return }
        let id = UUID().uuidString
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let object: [String: Any] = ["kind": "registerPushToken", "requestID": id, "token": token, "environment": environment]
        sendToMac(object, id: id, expect: "pushRegistered", timeout: 15) { data in
            let reply = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            if reply?["status"] as? String == "registered" { defaults.set(token, forKey: "jarvis.push.registeredToken") }
        }
    }

    private func deliverMacReply(_ id: String, _ data: Data?) {
        macReplies.removeValue(forKey: id)?(data)
    }

    /// 근거리 연결이 살아 있으면 근거리로, 아니면 등록된 키로 Tailscale 원격 요청을 보낸다.
    /// completion은 정확히 한 번, 메인 스레드에서 호출된다 (응답 또는 nil = 실패/시간 초과).
    private func sendToMac(_ object: [String: Any], id: String, expect: String, timeout: Double,
                           completion: @escaping (Data?) -> Void) {
        macReplies[id] = completion
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            self?.deliverMacReply(id, nil)
        }
        if connected, let peer = trustedPeer, session.connectedPeers.contains(peer) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { deliverMacReply(id, nil); return }
            do { try session.send(data, toPeers: [peer], with: .reliable) } catch { deliverMacReply(id, nil) }
            return
        }
        var remote = object
        remote["sentAt"] = Date().timeIntervalSince1970   // Mac은 60초 이내 요청만 받는다
        guard foreground, remembered, let secret = savedSecret, let mac = JARVISRemoteWire.mac,
              let frame = try? JARVISRemoteWire.encode(remote, secret: secret, response: false) else {
            deliverMacReply(id, nil); return
        }
        let c = NWConnection(host: NWEndpoint.Host(mac), port: JARVISRemoteWire.port, using: .tcp)
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let c else { return }
            Task { @MainActor in
                guard let self else { c.cancel(); return }
                if case .ready = state {
                    c.stateUpdateHandler = nil
                    c.send(content: frame, completion: .contentProcessed { error in
                        guard error == nil else {
                            c.cancel()
                            Task { @MainActor in self.deliverMacReply(id, nil) }
                            return
                        }
                        JARVISRemoteWire.read(c) { data in
                            c.cancel()
                            Task { @MainActor in
                                guard let data, let clear = try? JARVISRemoteWire.decode(data, secret: secret, response: true),
                                      let reply = (try? JSONSerialization.jsonObject(with: clear)) as? [String: Any],
                                      reply["kind"] as? String == expect, reply["requestID"] as? String == id else {
                                    self.deliverMacReply(id, nil); return
                                }
                                self.deliverMacReply(id, clear)
                            }
                        }
                    })
                } else if case .failed = state {
                    c.cancel()
                    self.deliverMacReply(id, nil)
                }
            }
        }
        c.start(queue: .main)
    }

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
        if !remoteOnly && !searching && !connected {
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
        guard !remembered, invitedPeer == nil, pin.count == 12 && pin.allSatisfy(\.isNumber), peers.contains(peer) else {
            status = "맥에 표시된 숫자 12자리를 입력해 주세요."
            return
        }
        invitedPeer = peer
        pairingCode = pin
        let nonce = UUID().uuidString
        clientNonce = nonce
        serverNonce = nil
        status = "Mac 보안 확인 중"
        armHandshakeTimeout(nonce)
        // Do NOT send the PIN. Only an unpredictable nonce goes in context.
        browser.invitePeer(peer, to: session, withContext: Data(nonce.utf8), timeout: 25)
    }

    func disconnect() {
        guard !publishing else { return }
        guard JARVISRememberedPeer.forget() else {
            status = "기기 등록 삭제 실패 · 키체인을 확인하세요."
            return
        }
        stopRemoteRead()
        remoteOnly = false
        remoteStatus = "원격 조회 전"
        savedSecret = nil
        remembered = false
        retryTask?.cancel()
        retryTask = nil
        clearHandshake()
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

    private func sendPairProof(_ proof: String, phoneKey: String?, to peer: MCPeerID) {
        var message = ["kind": "pairProof", "proof": proof]
        if let phoneKey { message["phoneKey"] = phoneKey }
        guard session.connectedPeers.contains(peer),
              let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            status = "Mac 보안 확인 실패"
            clearHandshake()
            session.disconnect()
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
        guard !remoteOnly, session.connectedPeers.contains(peer),
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
            var phoneKey: String?
            if resuming {
                guard object["mode"] as? String == "resume" else { return }
                boundClient = client
                boundServer = server
            } else {
                guard object["mode"] as? String == "register", let macKey = object["macKey"] as? String else { return }
                let key = Curve25519.KeyAgreement.PrivateKey()
                let pub = key.publicKey.rawRepresentation.base64EncodedString()
                guard let derived = JARVISRememberedPeer.derive(privateKey: key, remote: macKey, client: client, server: server) else { return }
                nextSecret = derived
                phoneKey = pub
                boundClient = client + "|" + pub
                boundServer = server + "|" + macKey
            }
            guard let bc = boundClient, let bs = boundServer else { return }
            let proof = JARVISPairProof.hex(code: pin, role: "phone", client: bc, server: bs)
            sendPairProof(proof, phoneKey: phoneKey, to: peer)
            return
        }
        if kind == "pairAccepted" {
            guard invitedPeer == peer,
                  let client = boundClient, let server = boundServer,
                  let pin = pairingCode,
                  let macProof = object["proof"] as? String,
                  JARVISPairProof.verify(macProof, code: pin,
                      role: "mac", client: client, server: server) else {
                status = "맥 신원 검증 실패 · 일정을 전송하지 않았어요."
                clearHandshake()
                session.disconnect()
                return
            }
            if let nextSecret {
                guard JARVISRememberedPeer.save(nextSecret) else {
                    status = "기기 등록 저장 실패"
                    clearHandshake()
                    session.disconnect()
                    return
                }
                savedSecret = nextSecret
                remembered = true
            }
            stopRemoteRead()
            remoteStatus = "근거리 연결 사용 중 · 원격 조회 대기"
            trustedPeer = peer
            connected = true
            clearHandshake()
            setForeground(foreground)
            status = "Mac 연결됨"
            sync()
            refreshProjects()
            return
        }
        guard connected, trustedPeer == peer else { return }
        // SNS 응답: 기다리던 requestID일 때만 전달한다.
        if kind == "socialSnapshot" || kind == "socialApprovalResult" || kind == "pushRegistered" {
            if let id = object["requestID"] as? String { deliverMacReply(id, data) }
            return
        }
        if kind == "publishResult" {
            guard let id = publishRequestID, object["requestID"] as? String == id else { return }
            finishPublish(id, state: object["status"] as? String ?? "unconfirmed")
            return
        }
        if kind == "projectSnapshot" {
            guard let id = projectRequestID, object["requestID"] as? String == id else { return }
            projectRequestID = nil
            do {
                projectSnapshot = try JSONDecoder().decode(JARVISProjectSnapshot.self, from: data)
                projectStatus = "근거리 Mac 작업 기록 확인"
            } catch { projectStatus = "Mac 프로젝트 응답 해석 실패" }
            return
        }
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
            guard !remoteOnly, !peers.contains(peerID) else { return }
            peers.append(peerID)
            peers.sort { $0.displayName < $1.displayName }
            if remembered { resume(peerID) }
            else { status = "연결할 Mac을 선택해 주세요." }
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
            guard !remoteOnly else { return }
            switch state {
            case .connected:
                // Encrypted transport alone does not prove Mac identity.
                // Wait for BOTH HMAC proofs before any calendar transfer.
                stopSearch()
                status = "Mac 보안 확인 중"
            case .notConnected:
                guard trustedPeer == peerID || invitedPeer == peerID else { return }
                connected = false
                trustedPeer = nil
                clearHandshake()
                finishSync()
                status = "근거리 연결 끊김 · 아이폰 일정 보관 중"
                if !remoteProjectVerified { projectStatus = "근거리 연결 끊김 · 원격 조회 시도" }
                readRemoteProjects()
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
