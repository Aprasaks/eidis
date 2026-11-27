import Foundation
import AppKit
import ImageIO

/// 아이폰 자비스 SNS 화면용 데이터와 승인 처리 (SNS 영역 전용 파일).
///
/// 연결·암호화·기기 인증은 기존 JarvisMacNearbyCalendar가 그대로 맡는다.
/// 이 파일은 이미 인증된 요청에 대해 "무엇을 돌려줄지"만 정한다.
///
/// 보내는 것: 채널 공개 수치(팔로워·게시물 수), 검토 대기 캐러셀의 작은 미리보기,
///           캡션, 결과물 digest.
/// 보내지 않는 것: Meta 토큰, 원본 PNG, 작업 로그, 그 밖의 로컬 파일.
@MainActor
enum JarvisSocialRemote {
    /// 근거리·원격 통로 모두 메시지 하나가 500KB를 넘으면 버린다.
    /// 미리보기 이미지는 base64 합계가 이 값을 넘지 않을 때까지만 담는다.
    private static let previewBudget = 330_000
    private static let captionLimit = 2_400
    /// 원격(Tailscale) 통로에서 추가로 허용하는 메시지 종류. 이 두 개뿐이다.
    static let remoteKinds: Set<String> = ["socialSnapshotRequest", "approveSocialPost", "registerPushToken"]

    // MARK: Channel numbers (5분 캐시)

    private static var cachedChannels: [[String: Any]] = []
    private static var cachedAt: Date?
    private static var refreshing: Task<Void, Never>?

    private static func refreshChannels() async {
        async let instagram = JarvisMetaInstagramService.scanSaved()
        async let threads = JarvisMetaChannels.scanThreads()
        async let facebook = JarvisMetaChannels.scanFacebook()
        let ig = await instagram, th = await threads, fb = await facebook
        func row(_ name: String, _ connected: Bool, _ handle: String?, _ followers: Int?, _ posts: Int?, _ error: String?) -> [String: Any] {
            var item: [String: Any] = ["name": name, "connected": connected]
            if let handle { item["handle"] = handle }
            if let followers { item["followers"] = followers }
            if let posts { item["posts"] = posts }
            if let error { item["error"] = error }
            return item
        }
        cachedChannels = [
            row("Instagram", ig.connected, ig.username, ig.followersCount, ig.mediaCount, ig.error),
            row("Threads", th.connected, th.handle, th.followersCount, th.postsCount, th.error),
            row("Facebook", fb.connected, fb.handle, fb.followersCount, fb.postsCount, fb.error)
        ]
        cachedAt = Date()
    }

    /// 캐시가 오래됐으면 갱신하되, 아이폰의 10초 응답 제한을 넘지 않도록 최대 6초만 기다린다.
    private static func channels() async -> [[String: Any]] {
        if let cachedAt, Date().timeIntervalSince(cachedAt) < 300 { return cachedChannels }
        if refreshing == nil {
            refreshing = Task { await refreshChannels(); refreshing = nil }
        }
        let task = refreshing
        let deadline = Date().addingTimeInterval(6)
        while task != nil, refreshing != nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return cachedChannels
    }

    // MARK: Carousel preview

    /// 가장 최근의 "검토 대기" 또는 "승인됨(게시 대기)" 캐러셀.
    private static func latestCarousel() -> [String: Any]? {
        let root = JarvisCarouselRunner.root
        let dirs = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for dir in dirs {
            guard JarvisCarouselRunner.runDirectory(named: dir.lastPathComponent) != nil,
                  let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
                  let meta = try? JSONDecoder().decode(JarvisCarouselRunner.Meta.self, from: data),
                  ["review", "approved", "posted"].contains(meta.status),
                  let digest = JarvisCarouselRunner.contentDigest(of: dir),
                  let caption = try? String(contentsOf: dir.appendingPathComponent("caption.txt"), encoding: .utf8)
            else { continue }
            var previews: [String] = []
            var used = 0
            var total = 0
            for index in 1...12 {
                let file = dir.appendingPathComponent(String(format: "slide-%02d.png", index))
                guard FileManager.default.fileExists(atPath: file.path) else { break }
                total += 1
                guard let jpeg = thumbnail(file) else { continue }
                let encoded = jpeg.base64EncodedString()
                guard used + encoded.count <= previewBudget else { continue }
                used += encoded.count
                previews.append(encoded)
            }
            // Claude 시각 검수 결과: review.md 마지막 줄이 RESULT: PASS/FIXED 인지.
            let review = (try? String(contentsOf: dir.appendingPathComponent("review.md"), encoding: .utf8)) ?? ""
            let verdict = review.split(separator: "\n").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            let visualChecked = verdict == "RESULT: PASS" || verdict == "RESULT: FIXED"
            return [
                "runID": dir.lastPathComponent,
                "title": meta.title,
                "articleURL": meta.articleURL,
                "status": meta.status,
                "createdAt": ISO8601DateFormatter().string(from: meta.startedAt),
                "caption": String(caption.prefix(captionLimit)),
                "slideCount": total,
                "previews": previews,
                "digest": digest,
                "visualChecked": visualChecked,
                // Threads 글 (승인 범위에 포함) — 없으면 빈 문자열
                "threadText": (try? String(contentsOf: dir.appendingPathComponent("threads.txt"), encoding: .utf8)) ?? "",
                // 게시 완료면 인스타 링크 (JarvisInstagramPublisher가 publish.json에 기록)
                "permalink": (JarvisInstagramPublisher.record(dir)?["permalink"] as? String) ?? ""
            ]
        }
        return nil
    }

    /// 1080×1350 PNG → 긴 변 400px JPEG (장당 약 20~35KB).
    private static func thumbnail(_ file: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 400,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.62])
    }

    // MARK: Requests (JarvisMacNearbyCalendar가 인증을 마친 뒤 호출)

    /// kind "socialSnapshotRequest" → "socialSnapshot"
    static func snapshot(requestID: String) async -> [String: Any] {
        var reply: [String: Any] = [
            "kind": "socialSnapshot", "requestID": requestID,
            "checkedAt": ISO8601DateFormatter().string(from: Date()),
            "channels": await channels()
        ]
        if let carousel = latestCarousel() { reply["carousel"] = carousel }
        // 아이폰 위젯용 요약: 승인 대기 수, 22시 게시 예정 제목, YouTube 구독자 (성장 기록의 오늘 값)
        let queue = JarvisCarouselRunner.shared.approvalQueue()
        var summary: [String: Any] = ["waitingApprovals": queue.waiting]
        if let title = queue.approvedTitle { summary["approvedTitle"] = title }
        let today = JarvisGrowthLog.formatter().string(from: Date())
        if let subs = JarvisGrowthLog.shared.days[today]?["youtubeSubscribers"] { summary["youtubeSubscribers"] = subs }
        reply["summary"] = summary
        return reply
    }

    /// kind "registerPushToken" → "pushRegistered" (아이폰 잠금화면 알림용 기기 토큰 등록)
    static func registerPush(_ object: [String: Any], requestID: String) -> [String: Any] {
        let ok = (object["token"] as? String).map {
            JarvisPushNotifier.shared.register(token: $0, environment: object["environment"] as? String ?? "sandbox")
        } ?? false
        return ["kind": "pushRegistered", "requestID": requestID, "status": ok ? "registered" : "invalid"]
    }

    /// kind "approveSocialPost" → "socialApprovalResult"
    /// 필요한 값: runID, digest(아이폰이 본 버전), decision("approve"|"reject"), ownerApproved=true.
    static func decide(_ object: [String: Any], requestID: String) -> [String: Any] {
        func reply(_ status: String) -> [String: Any] {
            ["kind": "socialApprovalResult", "requestID": requestID, "status": status]
        }
        guard object["ownerApproved"] as? Bool == true,
              let runID = object["runID"] as? String,
              let digest = object["digest"] as? String,
              digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              let decision = object["decision"] as? String,
              ["approve", "reject"].contains(decision) else { return reply("invalid") }
        let result = JarvisCarouselRunner.shared.recordOwnerDecision(runID: runID, digest: digest,
                                                                     approve: decision == "approve")
        return reply(result.rawValue)
    }
}
