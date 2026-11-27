import Foundation
import Security

/// 왼쪽 패널 사이트 카드용 실제 상태 (읽기 전용, 공개 정보만).
///
/// - 사이트 응답: 실제 주소에 GET 요청 → HTTP 상태와 응답 시간
/// - 최근 커밋: GitHub 공개 API (공개 저장소, 토큰 없음 · 15분마다 저장소당 1~2회)
/// - 사이트별 한 줄: dechive.app 최신 글(feed.xml), 탁구협회 대회 정보 수집 작업 마지막 실행
/// 값을 확인하지 못하면 "확인 실패"로 표시하고 추정치를 만들지 않는다.
@MainActor
final class JarvisSitePulse: ObservableObject {
    static let shared = JarvisSitePulse()

    struct Pulse {
        var siteOK: Bool?
        var siteLabel = "확인 중…"
        var commitLabel: String?
        var detail: String?
        var note: String?
        var detailWarning = false
        var checkedAt: Date?
    }

    @Published private(set) var pulses: [JarvisWorkroomProject: Pulse] = [:]
    private var task: Task<Void, Never>?

    /// 카드별 실제 주소와 GitHub 저장소 (사용자 GitHub: Aprasaks)
    nonisolated static func site(_ project: JarvisWorkroomProject) -> (url: String, repo: String) {
        switch project {
        case .dev: ("https://dechive.dev", "dechive-site")
        case .app: ("https://dechive.app", "Aprasaks.github.io")
        case .gunsan: ("https://xn--6e0b287a.com", "gunsan-com")          // 군산.com
        case .tableTennis: ("https://gunsan-table-tennis-association.vercel.app", "gunsan-table-tennis-association")
        }
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(900)) } catch { return }
            }
        }
    }

    func refresh() async {
        // 카드마다 동시에 확인한다: 한 사이트가 느리거나 막혀도 나머지 카드는 바로 채워진다.
        await withTaskGroup(of: (JarvisWorkroomProject, Pulse).self) { group in
            for project in JarvisWorkroomProject.allCases {
                let previous = pulses[project] ?? Pulse()
                group.addTask { (project, await Self.check(project, previous)) }
            }
            for await (project, pulse) in group { pulses[project] = pulse }
        }
    }

    nonisolated private static func check(_ project: JarvisWorkroomProject, _ previous: Pulse) async -> Pulse {
        var pulse = previous
        let (url, repo) = site(project)
        async let siteCheck = checkSite(url)
        async let commit = latestCommit(repo)
        switch project {
        case .app:
            // dechive.app 구독 팝업은 letter.dechive.app 폼을 그대로 쓰므로 구독자 명단은 하나다.
            async let subs = subscribers()
            async let post = latestPost()
            pulse.detail = await subs ?? "뉴스레터 구독자 수 확인 실패"
            pulse.note = await post ?? "최신 글 확인 실패"
        case .gunsan:
            // 사용자 확인(2026-11-27): 리빌드 1~4단계 반영 후 새 작업 대기 중.
            pulse.detail = "새 작업 대기 중 · 지도·맛집·리뷰·QR 예정"
        case .tableTennis:
            let crawl = await lastCrawl()
            pulse.detail = crawl.label
            pulse.detailWarning = crawl.warning
        case .dev:
            pulse.detail = nil
        }
        let (ok, label) = await siteCheck
        pulse.siteOK = ok
        pulse.siteLabel = label
        pulse.commitLabel = await commit
        pulse.checkedAt = Date()
        return pulse
    }

    // MARK: Fetchers

    nonisolated private static func get(_ url: URL, accept: String? = nil) async -> (Int, Data?, TimeInterval) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("JARVIS-SitePulse/1.0", forHTTPHeaderField: "User-Agent")
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        let started = Date()
        guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: req) else {
            return (0, nil, 0)
        }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data, Date().timeIntervalSince(started))
    }

    nonisolated private static func checkSite(_ address: String) async -> (Bool, String) {
        guard let url = URL(string: address) else { return (false, "주소 오류") }
        let (status, _, seconds) = await get(url)
        if status == 0 { return (false, "응답 없음") }
        let ms = Int(seconds * 1000)
        return (200..<400).contains(status) ? (true, "정상 · \(ms)ms") : (false, "HTTP \(status)")
    }

    nonisolated private static func latestCommit(_ repo: String) async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/Aprasaks/\(repo)/commits?per_page=1") else { return nil }
        let (status, data, _) = await get(url, accept: "application/vnd.github+json")
        guard status == 200, let data,
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let commit = list.first?["commit"] as? [String: Any],
              let message = commit["message"] as? String,
              let date = ((commit["committer"] as? [String: Any])?["date"] as? String)
                .flatMap(ISO8601DateFormatter().date(from:)) else { return nil }
        let title = message.split(separator: "\n").first.map(String.init) ?? message
        return relative(date) + " · " + String(title.prefix(48))
    }

    nonisolated private static let statsService = "dev.dechive.eidis.letter.stats.v2"
    nonisolated private static let statsAccount = "letter-stats-secret"
    nonisolated static let statsImportFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".jarvis-lab/secrets/letter-stats-secret")

    /// 집계 비밀 값: 자비스가 만든 Keychain 항목에서만 읽는다 (확인 팝업 없이, 없으면 nil).
    /// 처음 한 번은 설치 때 둔 0600 파일을 Keychain으로 옮기고 파일을 지운다.
    nonisolated private static func statsSecret() -> String? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: statsService,
            kSecAttrAccount as String: statsAccount
        ]
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail   // 팝업으로 멈추지 않게
        var output: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &output) == errSecSuccess,
           let data = output as? Data, let value = String(data: data, encoding: .utf8) { return value }
        guard let raw = try? String(contentsOf: statsImportFile, encoding: .utf8) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
        var insert = base
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(insert as CFDictionary, nil) == errSecSuccess {
            try? FileManager.default.removeItem(at: statsImportFile)
        }
        return value
    }

    /// 뉴스레터 구독자 수 (letter.dechive.app/api/letter-stats · 숫자만 · 비밀 값은 Keychain에만)
    nonisolated private static func subscribers() async -> String? {
        guard let secret = statsSecret(),
              let url = URL(string: "https://letter.dechive.app/api/letter-stats") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
        guard let (body, response) = try? await URLSession(configuration: .ephemeral).data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let active = json["active"] as? Int else { return nil }
        let bySource = json["bySource"] as? [String: Int] ?? [:]
        let week = json["newThisWeek"] as? Int ?? 0
        return "뉴스레터 구독자 \(active)명 · 메인 \(bySource["dechive.app"] ?? 0) · 레터 \(bySource["letter.dechive.app"] ?? 0)"
            + (week > 0 ? " · 이번 주 +\(week)" : "")
    }

    /// dechive.app 최신 글: feed.xml 첫 항목 제목
    nonisolated private static func latestPost() async -> String? {
        guard let url = URL(string: "https://dechive.app/feed.xml") else { return nil }
        let (status, data, _) = await get(url)
        guard status == 200, let data else { return nil }
        let xml = String(decoding: data, as: UTF8.self)
        let body = xml.range(of: "<item>").map { String(xml[$0.upperBound...]) }
            ?? xml.range(of: "<entry>").map { String(xml[$0.upperBound...]) } ?? ""
        guard let open = body.range(of: "<title>"), let close = body.range(of: "</title>", range: open.upperBound..<body.endIndex) else { return nil }
        let title = body[open.upperBound..<close.lowerBound]
            .replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : "최신 글 · " + String(title.prefix(40))
    }

    /// 탁구협회: 전북탁구협회 대회 정보 수집(sync-jbtta-2026) 마지막 실행
    nonisolated private static func lastCrawl() async -> (label: String, warning: Bool) {
        guard let url = URL(string: "https://api.github.com/repos/Aprasaks/gunsan-table-tennis-association/actions/workflows/sync-jbtta-2026.yml/runs?per_page=1") else {
            return ("대회 정보 수집 확인 실패", true)
        }
        let (status, data, _) = await get(url, accept: "application/vnd.github+json")
        guard status == 200, let data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let run = (json["workflow_runs"] as? [[String: Any]])?.first,
              let date = (run["created_at"] as? String).flatMap(ISO8601DateFormatter().date(from:)) else {
            return ("대회 정보 수집 확인 실패", true)
        }
        let result = (run["conclusion"] as? String) == "success" ? "성공" : ((run["conclusion"] as? String) ?? "진행 중")
        let stale = Date().timeIntervalSince(date) > 3 * 86_400
        // 사용자 확인(2026-11-27): 수집 코드는 정확하게 다시 고칠 예정. 지금은 수동 실행만 가능.
        return ("대회 정보 수집 · 마지막 \(relative(date)) \(result)" + (stale ? " · 수집 코드 수정 예정" : ""), stale)
    }

    nonisolated private static func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 3600 { return "\(max(1, Int(seconds / 60)))분 전" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))시간 전" }
        return "\(Int(seconds / 86_400))일 전"
    }
}
