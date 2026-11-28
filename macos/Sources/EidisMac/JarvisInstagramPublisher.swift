import Foundation
import AppKit
import Network
import CryptoKit

/// 승인된 캐러셀을 Instagram 공식 API(Content Publishing)로 게시한다 (SNS 영역 전용 파일).
///
/// 원칙
/// - 사용자가 아이폰(또는 Mac)에서 승인한 실행만 게시한다: meta.status == "approved" 이고,
///   approval.json의 digest가 지금 파일의 digest와 같아야 한다 (승인 이후 바뀌었으면 게시 안 함).
/// - 자동 게시는 22:00~23:30 KST 골든타임에 하루 한 번만 시도한다. 실패하면 자동 재시도하지 않는다.
/// - 중복 게시 방지: 게시 직전에 publishing 표시를 남기고, 결과를 모르는 상태로 끝나면
///   자동으로 다시 게시하지 않는다 (사용자가 인스타에서 확인 후 수동 처리).
/// - 이미지 공개 주소: Instagram API는 이미지를 공개 URL(JPEG)로만 받는다. 게시하는 몇 분 동안만
///   이 Mac의 Tailscale Funnel로 "슬라이드 JPEG만" 임의 경로에 공개하고, 끝나면 바로 끈다.
/// - 토큰은 Keychain에서 읽어 Authorization 헤더로만 보낸다. 로그·파일·URL에 남기지 않는다.
@MainActor
final class JarvisInstagramPublisher: ObservableObject {
    static let shared = JarvisInstagramPublisher()

    @Published private(set) var permissionStatus = "게시 권한 확인 전"
    @Published private(set) var permissionOK: Bool?
    @Published private(set) var publishing = false
    @Published private(set) var lastMessage: String?

    private static let seoul = TimeZone(identifier: "Asia/Seoul")!
    nonisolated private static let tailscale = "/usr/local/bin/tailscale"
    private static let filePort: UInt16 = 48781
    private var scheduleTask: Task<Void, Never>?
    private var fileServer: NWListener?

    // MARK: Schedule (22:00~23:30 KST)

    func startSchedule() {
        guard scheduleTask == nil else { return }
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.publishIfDue()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        NSLog("JARVIS SNS publisher active (approved carousels only, KST 22:00-23:30)")
    }

    private func publishIfDue() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.seoul
        let now = Date()
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        // P6 A3: 게시 15분 전에 Tailscale을 미리 확인한다 (11/27 22:00 실패 원인). 꺼져 있으면 폰으로 알린다.
        if (21 * 60 + 45 ..< 22 * 60).contains(minutes), !JarvisSNSPause.paused,
           Self.runs().contains(where: { Self.status(of: $0) == "approved" }) {
            let key = "eidis.ig.precheck." + Self.dayKey(now)
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                if !(await Self.tailscaleRunning()) {
                    JarvisPushNotifier.shared.send(title: "⚠️ 22시 인스타 게시 전에 확인",
                                                   body: "맥의 Tailscale이 꺼져 있어요. 켜야 게시할 수 있어요.", page: "approval")
                }
            }
        }
        guard (22 * 60 ..< 23 * 60 + 30).contains(minutes), !publishing, !JarvisSNSPause.paused else { return }
        // 하루 한 번: 오늘 이미 게시했거나 시도한 기록이 있으면 건너뛴다.
        let today = Self.dayKey(now)
        guard !Self.runs().contains(where: { Self.record($0)?["day"] as? String == today }) else { return }
        guard let dir = Self.runs().first(where: { Self.status(of: $0) == "approved" }) else { return }
        await publish(dir, trigger: "schedule")
    }

    // MARK: Permission check (읽기 전용)

    /// content_publishing_limit 조회는 게시 권한(instagram_content_publish)이 있어야 성공한다.
    func checkPermission() async {
        guard let token = JarvisMetaInstagramService.readToken() else {
            permissionOK = false; permissionStatus = "Instagram 토큰 없음"; return
        }
        let (host, account) = Self.endpoint()
        var parts = URLComponents(string: "https://\(host)/v27.0/\(account)/content_publishing_limit")!
        parts.queryItems = [URLQueryItem(name: "fields", value: "quota_usage,config")]
        let (status, json) = await Self.request(parts.url!, token: token)
        if status == 200 {
            let used = ((json?["data"] as? [[String: Any]])?.first?["quota_usage"] as? Int) ?? 0
            permissionOK = true
            permissionStatus = "게시 권한 확인 · 24시간 사용 \(used)/50"
        } else {
            permissionOK = false
            permissionStatus = Self.describe(status: status, json: json, missingPermissionHint: true)
        }
    }

    // MARK: Publish

    /// 승인된 실행 하나를 게시한다. trigger: "schedule" | "manual"
    func publish(_ dir: URL, trigger: String) async {
        guard !publishing else { return }
        publishing = true
        defer { publishing = false }
        func finish(_ result: String, _ extra: [String: Any] = [:]) {
            var record: [String: Any] = ["day": Self.dayKey(Date()), "trigger": trigger, "result": result,
                                         "at": ISO8601DateFormatter().string(from: Date())]
            extra.forEach { record[$0.key] = $0.value }
            Self.writeRecord(dir, record)
            lastMessage = result == "posted" ? "인스타 게시 완료" : "게시 실패 · " + (extra["error"] as? String ?? result)
            JarvisPushNotifier.shared.send(title: result == "posted" ? "✅ 인스타 게시 완료" : "⚠️ 인스타 게시 안 됨",
                                           body: result == "posted" ? "DECHIVE.WIKI 캐러셀이 올라갔어요" : (extra["error"] as? String ?? result))
            log(dir, lastMessage ?? "")
        }

        // 1) 승인 확인: 상태 + 승인 당시 digest와 지금 파일이 같은지
        guard Self.status(of: dir) == "approved",
              let approval = Self.json(dir.appendingPathComponent("approval.json")),
              let approved = approval["digest"] as? String,
              JarvisCarouselRunner.contentDigest(of: dir) == approved else {
            return finish("blocked", ["error": "승인 정보와 현재 결과물이 다릅니다. 다시 승인해 주세요."])
        }
        if let previous = Self.record(dir), previous["result"] as? String == "publishing" {
            return finish("unknown", ["error": "이전 게시 결과를 확인할 수 없어 자동 재게시하지 않습니다. 인스타에서 확인하세요."])
        }
        guard let token = JarvisMetaInstagramService.readToken() else { return finish("failed", ["error": "Instagram 토큰 없음"]) }
        guard let caption = try? String(contentsOf: dir.appendingPathComponent("caption.txt"), encoding: .utf8) else {
            return finish("failed", ["error": "캡션 없음"])
        }
        log(dir, "📤 인스타 게시 시작 (\(trigger == "schedule" ? "22시 자동" : "수동"))")

        // 2) 슬라이드를 JPEG로 변환 (Instagram API는 JPEG만 받는다)
        let secret = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let outbox = dir.appendingPathComponent("publish-jpeg", isDirectory: true)
        try? FileManager.default.removeItem(at: outbox)
        try? FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        var names: [String] = []
        for index in 1...10 {   // 캐러셀은 최대 10장
            let png = dir.appendingPathComponent(String(format: "slide-%02d.png", index))
            guard let image = NSImage(contentsOf: png),
                  let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else { break }
            let name = String(format: "slide-%02d.jpg", index)
            try? jpeg.write(to: outbox.appendingPathComponent(name))
            names.append(name)
        }
        guard names.count >= 2 else { return finish("failed", ["error": "슬라이드가 2장 미만"]) }

        // 3) 몇 분 동안만 공개 주소 열기 → 4) 게시 → 공개 주소 닫기 (성공·실패와 관계없이 항상 닫는다)
        let base = await openPublicFolder(outbox, secret: secret)
        let outcome: (String, [String: Any])
        if let base {
            log(dir, "🌐 슬라이드 \(names.count)장 임시 공개 (게시 후 바로 닫음)")
            outcome = await upload(dir: dir, names: names, base: base, token: token, caption: caption, trigger: trigger)
        } else {
            outcome = ("failed", ["error": "공개 이미지 주소를 열지 못함 (Tailscale Funnel 설정 필요)"])
        }
        await closePublicFolder()
        finish(outcome.0, outcome.1)
    }

    /// 컨테이너 생성 → 캐러셀 → 처리 대기 → 게시. (결과, 기록할 값)을 돌려준다.
    private func upload(dir: URL, names: [String], base: String, token: String, caption: String,
                        trigger: String) async -> (String, [String: Any]) {
        // 4) 컨테이너 생성 → 캐러셀 → 처리 대기 → 게시
        let (host, account) = Self.endpoint()
        let mediaURL = URL(string: "https://\(host)/v27.0/\(account)/media")!
        var children: [String] = []
        for name in names {
            let (status, json) = await Self.request(mediaURL, token: token, form: [
                "image_url": base + name, "is_carousel_item": "true"])
            guard status == 200, let id = json?["id"] as? String else {
                return ("failed", ["error": Self.describe(status: status, json: json, missingPermissionHint: true)])
            }
            children.append(id)
        }
        let (cStatus, cJSON) = await Self.request(mediaURL, token: token, form: [
            "media_type": "CAROUSEL", "children": children.joined(separator: ","), "caption": caption])
        guard cStatus == 200, let container = cJSON?["id"] as? String else {
            return ("failed", ["error": Self.describe(status: cStatus, json: cJSON, missingPermissionHint: false)])
        }
        var ready = false
        for _ in 0..<20 {
            var parts = URLComponents(string: "https://\(host)/v27.0/\(container)")!
            parts.queryItems = [URLQueryItem(name: "fields", value: "status_code")]
            let (_, sJSON) = await Self.request(parts.url!, token: token)
            let code = sJSON?["status_code"] as? String
            if code == "FINISHED" { ready = true; break }
            if code == "ERROR" || code == "EXPIRED" { break }
            try? await Task.sleep(for: .seconds(3))
        }
        guard ready else { return ("failed", ["error": "Instagram이 캐러셀 처리를 끝내지 못함"]) }

        // 중복 게시 방지 표시 → 게시
        Self.writeRecord(dir, ["day": Self.dayKey(Date()), "trigger": trigger, "result": "publishing",
                               "at": ISO8601DateFormatter().string(from: Date())])
        let (pStatus, pJSON) = await Self.request(URL(string: "https://\(host)/v27.0/\(account)/media_publish")!,
                                                  token: token, form: ["creation_id": container])
        guard pStatus == 200, let media = pJSON?["id"] as? String else {
            return ("unknown", ["error": "게시 응답 확인 실패 · 인스타에서 직접 확인하세요. " +
                                     Self.describe(status: pStatus, json: pJSON, missingPermissionHint: false)])
        }
        var permalink = ""
        var linkParts = URLComponents(string: "https://\(host)/v27.0/\(media)")!
        linkParts.queryItems = [URLQueryItem(name: "fields", value: "permalink")]
        let (_, lJSON) = await Self.request(linkParts.url!, token: token)
        permalink = lJSON?["permalink"] as? String ?? ""
        JarvisCarouselRunner.shared.markPosted(dir)
        return ("posted", ["mediaID": media, "permalink": permalink])
    }

    // MARK: Temporary public folder (Tailscale Funnel → 127.0.0.1 전용 파일 서버)

    /// 127.0.0.1에서 /<secret>/slide-NN.jpg 만 응답하는 서버를 열고 Funnel로 외부 공개한다.
    private func openPublicFolder(_ folder: URL, secret: String) async -> String? {
        guard FileManager.default.isExecutableFile(atPath: Self.tailscale),
              let dns = await Self.tailscaleDNSName() else { return nil }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.filePort)!)
        guard let listener = try? NWListener(using: params) else { return nil }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                var body = Data(), status = "404 Not Found", type = "text/plain"
                let prefix = "/" + secret + "/"
                if path.hasPrefix(prefix) {
                    let name = String(path.dropFirst(prefix.count))
                    if name.range(of: "^slide-[0-9]{2}\\.jpg$", options: .regularExpression) != nil,
                       let file = try? Data(contentsOf: folder.appendingPathComponent(name)) {
                        body = file; status = "200 OK"; type = "image/jpeg"
                    }
                }
                let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
        fileServer = listener
        // Funnel이 꺼져 있으면 CLI가 관리자 페이지 안내를 띄우고 기다릴 수 있어 15초 제한을 둔다.
        guard await Self.run(Self.tailscale, ["funnel", "--bg", "--https=443", "http://127.0.0.1:\(Self.filePort)"]) == 0 else { return nil }
        let base = "https://\(dns)/\(secret)/"
        // 공개 주소가 실제로 열렸는지 확인 (최대 20초)
        for _ in 0..<10 {
            if let url = URL(string: base + "slide-01.jpg"),
               let (_, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200 { return base }
            try? await Task.sleep(for: .seconds(2))
        }
        return nil
    }

    private func closePublicFolder() async {
        _ = await Self.run(Self.tailscale, ["funnel", "--https=443", "off"])
        fileServer?.cancel()
        fileServer = nil
    }

    // MARK: Helpers

    private func log(_ dir: URL, _ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        if let data = (stamp + "  " + line + "\n").data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: dir.appendingPathComponent("run.log")) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        }
        JarvisCarouselRunner.shared.noteExternal(dir, line)
    }

    private static func endpoint() -> (host: String, account: String) {
        JarvisMetaInstagramService.savedMode() == .facebookBusiness
            ? ("graph.facebook.com", JarvisMetaInstagramService.accountID)
            : ("graph.instagram.com", "me")
    }

    nonisolated private static func request(_ url: URL, token: String, form: [String: String]? = nil) async -> (Int, [String: Any]?) {
        var req = URLRequest(url: url)
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        if let form {
            req.httpMethod = "POST"
            // 캡션의 &, =, +, 줄바꿈까지 안전하게: 영숫자와 -._~ 외에는 모두 퍼센트 인코딩.
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            let body = form.map { key, value in
                key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
            }.joined(separator: "&")
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(body.utf8)
        }
        guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: req) else { return (0, nil) }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0,
                (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    }

    nonisolated private static func describe(status: Int, json: [String: Any]?, missingPermissionHint: Bool) -> String {
        let error = json?["error"] as? [String: Any]
        let code = error?["code"] as? Int ?? 0
        let message = (error?["message"] as? String).map { String($0.prefix(140)) } ?? "HTTP \(status)"
        switch code {
        case 190: return "인증 만료 · 토큰 재발급 필요"
        case 10, 200, 3:
            return missingPermissionHint ? "게시 권한 없음 · 토큰에 instagram_content_publish 필요" : "권한 부족 · " + message
        case 4, 17, 32, 613, 9: return "호출 한도 초과 · 잠시 후 다시"
        default: return status == 0 ? "네트워크 오류" : message
        }
    }

    /// 외부 명령은 백그라운드에서, 최대 timeout초만 기다린다 (자비스 화면이 멈추지 않게).
    nonisolated private static func run(_ path: String, _ arguments: [String], timeout: Double = 15) async -> Int32 {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return -1 }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { usleep(100_000) }
            if process.isRunning { process.terminate(); return -2 }
            return process.terminationStatus
        }.value
    }

    /// Tailscale이 실제로 연결돼 있는지 (BackendState == "Running")
    nonisolated static func tailscaleRunning() async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: tailscale) else { return false }
        return await Task.detached { () -> Bool in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: tailscale)
            process.arguments = ["status", "--json"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return json?["BackendState"] as? String == "Running"
        }.value
    }

    nonisolated private static func tailscaleDNSName() async -> String? {
        await Task.detached { () -> String? in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: tailscale)
            process.arguments = ["status", "--json"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let me = json["Self"] as? [String: Any], let dns = me["DNSName"] as? String else { return nil }
            let name = dns.hasSuffix(".") ? String(dns.dropLast()) : dns
            return name.range(of: "^[a-z0-9-]+\\.[a-z0-9-]+\\.ts\\.net$", options: .regularExpression) != nil ? name : nil
        }.value
    }

    static func runs() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: JarvisCarouselRunner.root, includingPropertiesForKeys: nil)) ?? [])
            .filter { JarvisCarouselRunner.runDirectory(named: $0.lastPathComponent) != nil }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func status(of dir: URL) -> String? { json(dir.appendingPathComponent("meta.json"))?["status"] as? String }
    static func record(_ dir: URL) -> [String: Any]? { json(dir.appendingPathComponent("publish.json")) }

    private static func writeRecord(_ dir: URL, _ record: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("publish.json"))
        }
    }

    private static func json(_ url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = seoul
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
}
