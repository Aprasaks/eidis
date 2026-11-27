import Foundation

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
        for project in JarvisWorkroomProject.allCases {
            var pulse = pulses[project] ?? Pulse()
            let (url, repo) = Self.site(project)
            let (ok, label) = await Self.checkSite(url)
            pulse.siteOK = ok
            pulse.siteLabel = label
            pulse.commitLabel = await Self.latestCommit(repo)
            switch project {
            case .app:
                pulse.detail = await Self.latestPost() ?? "최신 글 확인 실패"
            case .gunsan:
                // 사용자 확인(2026-11-27): 리빌드 1~4단계 반영 후 새 작업 대기 중.
                pulse.detail = "새 작업 대기 중 · 지도·맛집·리뷰·QR 예정"
            case .tableTennis:
                let crawl = await Self.lastCrawl()
                pulse.detail = crawl.label
                pulse.detailWarning = crawl.warning
            case .dev:
                pulse.detail = nil
            }
            pulse.checkedAt = Date()
            pulses[project] = pulse
        }
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
