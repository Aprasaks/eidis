import Foundation

/// 승인된 실행의 threads.txt를 Threads 공식 API로 게시한다 (SNS 영역 전용 파일).
///
/// - 대상: meta.status가 approved 또는 posted 이고, threads.txt가 있고, 아직 Threads 게시 기록이 없는 실행.
/// - 승인 확인: approval.json digest == 지금 파일 digest (threads.txt 포함). 바뀌었으면 게시하지 않는다.
/// - 시간: 09:00~11:00 KST (미국 저녁) 하루 한 번만 시도, 실패해도 자동 재시도하지 않는다.
/// - 중복 방지: 게시 직전 "publishing" 기록 → 결과 불명이면 다시 올리지 않는다.
/// - 토큰은 Keychain에서 읽어 Authorization 헤더로만 보낸다.
@MainActor
final class JarvisThreadsPublisher: ObservableObject {
    static let shared = JarvisThreadsPublisher()

    @Published private(set) var permissionStatus = "Threads 게시 권한 확인 전"
    @Published private(set) var permissionOK: Bool?
    @Published private(set) var publishing = false
    private var task: Task<Void, Never>?

    func startSchedule() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.publishIfDue()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    static func record(_ dir: URL) -> [String: Any]? {
        (try? Data(contentsOf: dir.appendingPathComponent("threads-publish.json")))
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    }

    /// 다음에 올라갈 Threads 글이 있는 승인된 실행
    static func nextApproved() -> URL? {
        JarvisInstagramPublisher.runs().first { dir in
            ["approved", "posted"].contains(JarvisInstagramPublisher.status(of: dir) ?? "")
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent("threads.txt").path)
                && record(dir) == nil
        }
    }

    private func publishIfDue() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = Date()
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard (9 * 60 ..< 11 * 60).contains(minutes), !publishing else { return }
        let today = JarvisDailyTimeline.dayKey(now)
        guard !JarvisInstagramPublisher.runs().contains(where: { Self.record($0)?["day"] as? String == today }),
              let dir = Self.nextApproved() else { return }
        await publish(dir, trigger: "schedule")
    }

    /// threads_publishing_limit 조회는 게시 권한(threads_content_publish)이 있어야 성공한다.
    func checkPermission() async {
        guard let token = JarvisMetaChannels.threadsToken(),
              let url = URL(string: "https://graph.threads.net/v1.0/me/threads_publishing_limit?fields=quota_usage") else {
            permissionOK = false; permissionStatus = "Threads 토큰 없음"; return
        }
        let (status, json) = await Self.request(url, token: token)
        if status == 200 {
            let used = ((json?["data"] as? [[String: Any]])?.first?["quota_usage"] as? Int) ?? 0
            permissionOK = true
            permissionStatus = "Threads 게시 권한 확인 · 24시간 \(used)/250"
        } else {
            permissionOK = false
            permissionStatus = Self.describe(status, json)
        }
    }

    func publish(_ dir: URL, trigger: String) async {
        guard !publishing else { return }
        publishing = true
        defer { publishing = false }
        let day = JarvisDailyTimeline.dayKey(Date())
        func finish(_ result: String, _ extra: [String: Any] = [:]) {
            var record: [String: Any] = ["day": day, "trigger": trigger, "result": result,
                                         "at": ISO8601DateFormatter().string(from: Date())]
            extra.forEach { record[$0.key] = $0.value }
            if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: dir.appendingPathComponent("threads-publish.json"))
            }
            JarvisCarouselRunner.shared.noteExternal(dir, result == "posted" ? "🧵 Threads 게시 완료" : "🧵 Threads 게시 안 됨 · " + (extra["error"] as? String ?? result))
        }
        guard ["approved", "posted"].contains(JarvisInstagramPublisher.status(of: dir) ?? ""),
              let approval = (try? Data(contentsOf: dir.appendingPathComponent("approval.json")))
                .flatMap({ (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }),
              let approved = approval["digest"] as? String,
              JarvisCarouselRunner.contentDigest(of: dir) == approved else {
            return finish("blocked", ["error": "승인 정보와 현재 글이 다릅니다. 다시 승인해 주세요."])
        }
        if Self.record(dir)?["result"] as? String == "publishing" {
            return finish("unknown", ["error": "이전 게시 결과 불명 · Threads에서 확인하세요"])
        }
        guard let token = JarvisMetaChannels.threadsToken() else { return finish("failed", ["error": "Threads 토큰 없음"]) }
        guard let raw = try? String(contentsOf: dir.appendingPathComponent("threads.txt"), encoding: .utf8) else {
            return finish("failed", ["error": "threads.txt 없음"])
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { return finish("failed", ["error": "글 길이 오류 (\(text.count)자, 최대 500)"]) }

        let base = "https://graph.threads.net/v1.0/me"
        let (cStatus, cJSON) = await Self.request(URL(string: base + "/threads")!, token: token,
                                                  form: ["media_type": "TEXT", "text": text])
        guard cStatus == 200, let container = cJSON?["id"] as? String else {
            return finish("failed", ["error": Self.describe(cStatus, cJSON)])
        }
        try? await Task.sleep(for: .seconds(5))   // Meta 권장: 컨테이너 생성 후 잠시 대기
        if let data = try? JSONSerialization.data(withJSONObject: ["day": day, "result": "publishing"]) {
            try? data.write(to: dir.appendingPathComponent("threads-publish.json"))
        }
        let (pStatus, pJSON) = await Self.request(URL(string: base + "/threads_publish")!, token: token,
                                                  form: ["creation_id": container])
        guard pStatus == 200, let media = pJSON?["id"] as? String else {
            return finish("unknown", ["error": "게시 응답 확인 실패 · Threads에서 확인하세요. " + Self.describe(pStatus, pJSON)])
        }
        var linkParts = URLComponents(string: "https://graph.threads.net/v1.0/\(media)")!
        linkParts.queryItems = [URLQueryItem(name: "fields", value: "permalink")]
        let (_, lJSON) = await Self.request(linkParts.url!, token: token)
        finish("posted", ["mediaID": media, "permalink": lJSON?["permalink"] as? String ?? ""])
    }

    // MARK: HTTP

    nonisolated private static func request(_ url: URL, token: String, form: [String: String]? = nil) async -> (Int, [String: Any]?) {
        var req = URLRequest(url: url)
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        if let form {
            req.httpMethod = "POST"
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            let body = form.map { $0.key + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }
                .joined(separator: "&")
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(body.utf8)
        }
        guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: req) else { return (0, nil) }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    }

    nonisolated private static func describe(_ status: Int, _ json: [String: Any]?) -> String {
        let error = json?["error"] as? [String: Any]
        switch error?["code"] as? Int ?? 0 {
        case 190: return "인증 만료 · Threads 토큰 재발급 필요"
        case 10, 200, 3: return "게시 권한 없음 · 토큰에 threads_content_publish 필요"
        case 4, 17, 32, 613: return "호출 한도 초과"
        default: return status == 0 ? "네트워크 오류" : ((error?["message"] as? String).map { String($0.prefix(140)) } ?? "HTTP \(status)")
        }
    }
}
