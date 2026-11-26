import Foundation
import Combine
import Darwin

struct JarvisKnowledgeTopic: Codable, Identifiable {
    let number: Int
    let code: String
    let title: String
    let category: String
    let slug: String?
    var id: String { code }
    var resolvedSlug: String { slug ?? "knowledge-" + code.lowercased() }
}

struct JarvisKnowledgeCatalog: Codable {
    let schemaVersion: Int
    let sourceSha256: String
    let continuationCode: String
    let topics: [JarvisKnowledgeTopic]

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".jarvis-lab/knowledge-pilot", isDirectory: true)
    }

    static func load(root: URL = root) throws -> Self {
        let data = try Data(contentsOf: root.appendingPathComponent("catalog/topics.json"))
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1, catalog.topics.count == 569,
              catalog.topics.map(\.number) == Array(1...569),
              Set(catalog.topics.map(\.code)).count == 569,
              Set(catalog.topics.map(\.category)).count == 24,
              catalog.topics.contains(where: { $0.code == catalog.continuationCode }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return catalog
    }
}

/// Count reservations, not successes: failed model starts also consume quota.
/// An exclusive file creation makes the limit survive restarts and simultaneous
/// attempts. These markers contain no credentials and are never auto-deleted.
enum JarvisKnowledgeDailyBudget {
    static let limit = 3

    static func dayKey(at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }

    private static func folder(root: URL, at date: Date) -> URL {
        root.appendingPathComponent("daily-budget", isDirectory: true)
            .appendingPathComponent(dayKey(at: date), isDirectory: true)
    }

    static func used(root: URL = JarvisKnowledgeCatalog.root, at date: Date = Date()) -> Int {
        let day = folder(root: root, at: date)
        return (1...limit).filter {
            FileManager.default.fileExists(atPath: day.appendingPathComponent("slot-\($0)").path)
        }.count
    }


    // Historical reservations were combined through Nov 27. Never reinterpret
    // or delete those markers; the split policy applies from the next KST day.
    static let splitPolicyDay = "2026-11-28"
    static let repairLimit = 3

    static func usesSeparateRepairs(at date: Date = Date()) -> Bool {
        dayKey(at: date) >= splitPolicyDay
    }

    private static func repairFolder(root: URL, at date: Date) -> URL {
        root.appendingPathComponent("repair-budget", isDirectory: true)
            .appendingPathComponent(dayKey(at: date), isDirectory: true)
    }

    private static func validRepairCode(_ code: String) -> Bool {
        code.range(of: #"^K[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil
    }

    static func repairUsed(root: URL = JarvisKnowledgeCatalog.root, at date: Date = Date()) -> Int {
        let dir = repairFolder(root: root, at: date)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { validRepairCode($0) }.count
    }

    static func reserveRepair(topicCode: String, root: URL = JarvisKnowledgeCatalog.root,
                              at date: Date = Date()) throws -> Bool {
        guard usesSeparateRepairs(at: date), validRepairCode(topicCode) else { return false }
        let dir = repairFolder(root: root, at: date)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let lock = Darwin.open(dir.appendingPathComponent(".lock").path,
                               O_WRONLY | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard lock >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(lock, LOCK_UN) }
        guard repairUsed(root: root, at: date) < repairLimit else { return false }
        let target = dir.appendingPathComponent(topicCode)
        let fd = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        if fd >= 0 { Darwin.close(fd); return true }
        if errno == EEXIST { return false }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    static func stagedToday(root: URL = JarvisKnowledgeCatalog.root, at date: Date = Date()) -> [String] {
        let day = dayKey(at: date)
        let dir = root.appendingPathComponent("night-shifts").appendingPathComponent(day)
        if let data = try? Data(contentsOf: dir.appendingPathComponent("progress.json")),
           let progress = try? JSONDecoder().decode([String: [String]].self, from: data),
           progress["day"] == [day] {
            return (progress["staged"] ?? []).filter { validRepairCode($0) }
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("summary.json")),
           let summary = try? JSONDecoder().decode([String: String].self, from: data),
           summary["day"] == day {
            return (summary["staged"] ?? "").split(separator: ",").map(String.init).filter { validRepairCode($0) }
        }
        return []
    }

    static func reserve(root: URL = JarvisKnowledgeCatalog.root, at date: Date = Date()) throws -> Int? {
        let day = folder(root: root, at: date)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        for slot in 1...limit {
            let target = day.appendingPathComponent("slot-\(slot)").path
            let fd = Darwin.open(target, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
            if fd >= 0 {
                Darwin.close(fd)
                return slot
            }
            if errno != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        return nil
    }
}

struct JarvisKnowledgePublicArticle: Decodable {
    let title: String
    let slug: String
}

@MainActor
final class JarvisKnowledgeCatalogMonitor: ObservableObject {
    @Published private(set) var catalog: JarvisKnowledgeCatalog?
    @Published private(set) var publicArticles: [JarvisKnowledgePublicArticle]?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var error: String?

    struct Reply: Decodable { let result: [JarvisKnowledgePublicArticle] }
    var publicSlugs: Set<String> { Set((publicArticles ?? []).map(\.slug)) }
    var mappedCount: Int {
        (catalog?.topics ?? []).filter { publicSlugs.contains($0.resolvedSlug) }.count
    }

    init() {
        do { catalog = try JarvisKnowledgeCatalog.load() }
        catch { self.error = "내부 집필 목록 읽기 실패" }
    }

    func refresh() async {
        if catalog == nil {
            do { catalog = try JarvisKnowledgeCatalog.load() }
            catch { self.error = "내부 집필 목록 읽기 실패"; return }
        }
        var url = URLComponents(string: "https://5e2ms6sb.api.sanity.io/v2026-09-16/data/query/production")!
        url.queryItems = [
            URLQueryItem(name: "query", value: "*[_type==\"knowledge\" && status==\"published\" && humanVerified==true && defined(slug.current)]{title,\"slug\":slug.current}"),
            URLQueryItem(name: "perspective", value: "published")
        ]
        do {
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let articles = try JSONDecoder().decode(Reply.self, from: data).result
            guard Set(articles.map(\.slug)).count == articles.count else { throw CocoaError(.fileReadCorruptFile) }
            publicArticles = articles
            checkedAt = Date()
            error = nil
        } catch {
            if !Task.isCancelled { self.error = "공개 현황 갱신 실패 · 마지막 확인값 유지" }
        }
    }

    func isPublished(_ topic: JarvisKnowledgeTopic) -> Bool {
        publicSlugs.contains(topic.resolvedSlug)
    }

    // Continue at the explicitly established editorial cursor, never silently
    // mark earlier holes as published, and never use the public count as index.
    func nextCandidate(afterStaged staged: Set<String>) -> JarvisKnowledgeTopic? {
        guard let catalog, publicArticles != nil,
              let start = catalog.topics.firstIndex(where: { $0.code == catalog.continuationCode }) else { return nil }
        return catalog.topics[start...].first { !isPublished($0) && !staged.contains($0.code) }
    }
}
