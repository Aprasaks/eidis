import Foundation
import SwiftUI

/// Dashboard types correspond to actual, connected read-only local sources.
/// External research/video analytics cannot be presented as available until connected.
enum JarvisLiveDashboardMode: String, CaseIterable, Equatable {
    case overview, projects, knowledge, system
    var title: String {
        switch self {
        case .overview: "LIVE OVERVIEW"
        case .projects: "PROJECT INTELLIGENCE"
        case .knowledge: "KNOWLEDGE ARCHIVE"
        case .system: "SYSTEM TELEMETRY"
        }
    }
    var koreanName: String {
        switch self {
        case .overview: "전체 현황"
        case .projects: "프로젝트 현황"
        case .knowledge: "저장 자료 분석"
        case .system: "자비스 시스템 상태"
        }
    }
}

/// Explicit local dashboard requests take priority over generic web searches.
/// No user text is forwarded to third-party search providers.
enum JarvisLiveDashboardIntent: Equatable {
    case show(JarvisLiveDashboardMode)
    case hide
    case unavailable

    static func parse(_ phrase: String) -> Self? {
        let text = phrase.lowercased().filter { !$0.isWhitespace && !$0.isNewline }
        let dashboard = text.contains("대시보드") || text.contains("현황판") || text.contains("통계") || text.contains("관제실")
        let overview = ["전체현황", "전체상황", "내상황", "종합현황", "통합현황", "전반적인현황", "모든현황"].contains { text.contains($0) }
        let project = ["프로젝트", "작업현황", "할일", "해야할일", "진행상황"].contains { text.contains($0) }
        let knowledge = ["보관함", "저장자료", "저장한자료", "내자료", "지식", "기억통계", "자료분석"].contains { text.contains($0) }
        let system = ["자비스상태", "시스템상태", "서버상태", "ollama상태", "로컬서버", "시스템진단"].contains { text.contains($0) }
        let close = ["닫아", "꺼줘", "숨겨", "치워", "내려", "접어"].contains { text.contains($0) }
        let returnToCore = ["원래대로돌아", "기본화면으로", "처음화면으로", "코어중앙으로", "관제실닫아", "관제실꺼", "전체현황닫아"].contains { text.contains($0) }
        if returnToCore || (dashboard && close) { return .hide }
        // GitHub account status is backed by a real read-only gh API call.
        let githubRequest = ["깃허브", "github", "깃전체", "깃프로젝트", "git현황",
                             "vercel", "버셀"]
            .contains { text.contains($0) }
        if githubRequest && ["보여", "열어", "띄워", "현황", "상태", "분석", "프로젝트", "전체"]
            .contains(where: { text.contains($0) }) {
            return .show(.overview)
        }
        let externalSignals = ["유튜브", "youtube", "뉴스", "날씨", "증시", "주가", "주식", "stock",
                               "깃허브", "github", "인스타", "instagram", "threads", "코인", "환율", "외부"]
        let external = externalSignals.contains { text.contains($0) }
        if external && (dashboard || text.contains("현황") || text.contains("분석") || text.contains("통계")) {
            return .unavailable
        }
        // A direct user command opens the immersive, one-screen dashboard.
        // Written without spaces or with natural variants, it is the same intent.
        let fullDashboard = ["전체대시보드", "통합대시보드", "종합대시보드",
                             "전체화면대시보드", "풀스크린대시보드", "전체관제실"]
            .contains { text.contains($0) }
        let openWords = ["열어", "켜줘", "켜", "띄워", "보여", "실행해", "실행", "표시해"]
        if fullDashboard && openWords.contains(where: { text.contains($0) }) {
            return .show(.overview)
        }
        let showing = ["보여", "띄워", "열어", "알려", "확인", "분석", "현황", "상태", "통계", "갱신", "새로고침"].contains { text.contains($0) }
        guard showing else { return nil }
        if overview { return .show(.overview) }
        if system && (dashboard || text.contains("자비스") || text.contains("시스템") || text.contains("서버") || text.contains("ollama")) {
            return .show(.system)
        }
        if knowledge && (dashboard || text.contains("분석") || text.contains("통계") || text.contains("현황")) {
            return .show(.knowledge)
        }
        if project && (dashboard || text.contains("현황") || text.contains("진행상황") || text.contains("분석")) {
            return .show(.projects)
        }
        if dashboard && !project && !knowledge && !system {
            let general = ["전체", "종합", "통합", "내현황", "자비스대시보드", "실시간대시보드", "대시보드띄워", "대시보드보여", "현황판띄워", "관제실보여", "관제실띄워", "관제실열어"].contains {
                text.contains($0)
            }
            return general ? .show(.overview) : .unavailable
        }
        return nil
    }
}

private struct LiveVaultReply: Decodable {
    let total: Int
    let counts: [String: Int]
    let items: [JarvisVaultItem]
}
private struct LiveDiagnosticsReply: Decodable {
    struct Database: Decodable { let status: String }
    let database: Database
}
private struct LiveStatusReply: Decodable {
    let profileCount: Int
    let memoryCount: Int
}
private struct LiveOllamaReply: Decodable { let version: String }

struct JarvisRecordedActivity: Decodable, Identifiable {
    let id: Int
    let category: String
    let result: String
    let createdAt: String
}
private struct LiveActivityReply: Decodable { let items: [JarvisRecordedActivity] }

struct JarvisVerifiedSourceCheck: Identifiable {
    let id = UUID()
    let at: Date
    let source: String
    let success: Bool
    let detail: String
}

/// Polling while visible, stopped immediately on hide/Esc. Each displayed
/// number comes from its named source with a successful HTTP response.
@MainActor
final class JarvisLiveDashboard: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var mode: JarvisLiveDashboardMode = .overview
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var errorText: String?
    @Published private(set) var projects: [WorkProject] = []
    @Published private(set) var projectsReady = false
    @Published private(set) var vaultTotal: Int?
    @Published private(set) var vaultCounts: [String: Int] = [:]
    @Published private(set) var recentItems: [JarvisVaultItem] = []
    @Published private(set) var databaseStatus: String?
    @Published private(set) var profileCount: Int?
    @Published private(set) var ollamaVersion: String?
    @Published private(set) var ollamaChecked = false
    @Published private(set) var recordedActivity: [JarvisRecordedActivity] = []
    @Published private(set) var activityChecked = false
    @Published private(set) var sourceChecks: [JarvisVerifiedSourceCheck] = []
    @Published private(set) var gitSnapshot: JarvisLocalGitSnapshot?
    @Published private(set) var gitIsLoading = false
    private var gitTask: Task<Void, Never>?
    private var gitLastCheckedAt: Date?
    @Published private(set) var githubSnapshot: JarvisGitHubRemoteSnapshot?
    @Published private(set) var githubIsLoading = false
    private var githubTask: Task<Void, Never>?
    private var githubLastCheckedAt: Date?
    @Published private(set) var vercelSnapshot: JarvisVercelSnapshot?
    @Published private(set) var vercelIsLoading = false
    private var vercelTask: Task<Void, Never>?
    private var vercelLastCheckedAt: Date?

    private let session: URLSession
    private var pollingTask: Task<Void, Never>?
    private var revision = UUID()
    static let intervalNanoseconds: UInt64 = 7_000_000_000

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        session = URLSession(configuration: config)
    }

    var taskTotal: Int { projects.reduce(0) { $0 + $1.tasks.count } }
    var todo: Int { projects.reduce(0) { $0 + $1.taskCounts.todo } }
    var doing: Int { projects.reduce(0) { $0 + $1.taskCounts.doing } }
    var blocked: Int { projects.reduce(0) { $0 + $1.taskCounts.blocked } }
    var done: Int { projects.reduce(0) { $0 + $1.taskCounts.done } }

    private func fetch<T: Decodable>(_ endpoint: String, port: Int = 8765) async throws -> T {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(endpoint)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= 2_000_000 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func show(_ selected: JarvisLiveDashboardMode) async -> String {
        pollingTask?.cancel()
        gitTask?.cancel()
        gitTask = nil
        githubTask?.cancel()
        githubTask = nil
        vercelTask?.cancel()
        vercelTask = nil
        let id = UUID()
        revision = id
        isVisible = true
        mode = selected
        isLoading = true
        isRefreshing = false
        refreshedAt = nil
        errorText = nil
        projects = []
        projectsReady = false
        vaultTotal = nil
        vaultCounts = [:]
        recentItems = []
        databaseStatus = nil
        profileCount = nil
        ollamaVersion = nil
        ollamaChecked = false
        recordedActivity = []
        activityChecked = false
        sourceChecks = []
        gitSnapshot = nil
        gitLastCheckedAt = nil
        gitIsLoading = false
        githubSnapshot = nil
        githubLastCheckedAt = nil
        githubIsLoading = false
        vercelSnapshot = nil
        vercelLastCheckedAt = nil
        vercelIsLoading = false
        let loaded = await refresh(id: id)
        guard isVisible && revision == id && !Task.isCancelled else { return "" }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: Self.intervalNanoseconds) }
                catch { return }
                guard let self, !Task.isCancelled, self.isVisible, self.revision == id else { return }
                _ = await self.refresh(id: id)
            }
        }
        return loaded ? "데카이브, 실제 로컬 데이터를 바탕으로 \(selected.koreanName) 대시보드를 열었습니다. 표시된 동안 약 7초 간격으로 갱신됩니다."
            : "\(selected.koreanName) 대시보드를 열었지만 일부 데이터를 가져오지 못했습니다. 연결 상태를 표시했습니다."
    }

    @discardableResult
    private func refresh(id: UUID) async -> Bool {
        guard isVisible && revision == id && !Task.isCancelled else { return false }
        isRefreshing = true
        let selected = mode
        // Only fetch the data sources needed for the active dashboard.
        let needsProjects = selected == .overview || selected == .projects
        let needsVault = selected == .overview || selected == .knowledge
        let needsStatus = selected == .overview || selected == .system
        if selected == .overview {
            startLocalGitScanIfNeeded(id: id)
            startGitHubScanIfNeeded(id: id)
            startVercelScanIfNeeded(id: id)
        }
        var success = true
        if needsProjects {
            do {
                let reply: WorkProjectsReply = try await fetch("/api/projects")
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                projects = reply.items
                projectsReady = true
                recordCheck("프로젝트 원장", success: true, detail: "\(projects.count)개 · 작업 \(taskTotal)건")
            } catch {
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                success = false
                projects = []
                projectsReady = false
                recordCheck("프로젝트 원장", success: false, detail: "연결 실패")
            }
        }
        if needsVault {
            do {
                let reply: LiveVaultReply = try await fetch("/api/vault?limit=12")
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                vaultTotal = reply.total
                vaultCounts = reply.counts
                recentItems = Array(reply.items.prefix(6))
                recordCheck("자료 보관함", success: true, detail: "활성 \(reply.total)건")
            } catch {
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                success = false
                vaultTotal = nil
                vaultCounts = [:]
                recentItems = []
                recordCheck("자료 보관함", success: false, detail: "연결 실패")
            }
        }
        if needsStatus {
            do {
                let diagnostics: LiveDiagnosticsReply = try await fetch("/api/diagnostics")
                let status: LiveStatusReply = try await fetch("/api/status")
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                databaseStatus = diagnostics.database.status
                profileCount = status.profileCount
                recordCheck("SQLite 진단", success: diagnostics.database.status == "ok",
                            detail: diagnostics.database.status == "ok" ? "정상" : diagnostics.database.status)
            } catch {
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                success = false
                databaseStatus = nil
                profileCount = nil
                recordCheck("SQLite 진단", success: false, detail: "연결 실패")
            }
            do {
                let ollama: LiveOllamaReply = try await fetch("/api/version", port: 11434)
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                ollamaVersion = ollama.version
                recordCheck("Ollama", success: true, detail: "v\(ollama.version)")
            } catch {
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                ollamaVersion = nil // A disconnected Ollama is a real status, not invented data.
                recordCheck("Ollama", success: false, detail: "연결 실패")
            }
            ollamaChecked = true
        }
        if selected == .overview {
            do {
                let events: LiveActivityReply = try await fetch("/api/activity")
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                recordedActivity = Array(events.items.prefix(18))
                activityChecked = true
                recordCheck("작업 이벤트 원장", success: true, detail: "\(events.items.count)건 조회")
            } catch {
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                activityChecked = false
                recordedActivity = []
                recordCheck("작업 이벤트 원장", success: false, detail: "연결 실패")
                success = false
            }
        }
        guard isVisible && revision == id && !Task.isCancelled else { return false }
        errorText = success ? nil : "일부 로컬 자료에 연결되지 않았습니다. 해당 값은 표시하지 않습니다."
        refreshedAt = Date()
        isLoading = false
        isRefreshing = false
        return success
    }

    private func recordCheck(_ source: String, success: Bool, detail: String) {
        // These entries represent completed, real HTTP checks. They are never
        // synthetic 'AI jobs' or invented progress indicators.
        sourceChecks.insert(JarvisVerifiedSourceCheck(at: Date(), source: source,
                                                      success: success, detail: detail), at: 0)
        if sourceChecks.count > 40 { sourceChecks.removeLast(sourceChecks.count - 40) }
    }

    private func startLocalGitScanIfNeeded(id: UUID) {
        guard gitTask == nil,
              gitLastCheckedAt.map({ Date().timeIntervalSince($0) > 25 }) ?? true else { return }
        gitIsLoading = true
        gitLastCheckedAt = Date()
        gitTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                JarvisLocalGitScanner.scan()
            }
            let snapshot = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, !Task.isCancelled, self.isVisible, self.revision == id else { return }
            self.gitSnapshot = snapshot
            self.gitIsLoading = false
            self.gitTask = nil
            self.recordCheck("로컬 Git", success: snapshot.error == nil,
                             detail: "\(snapshot.repositories.count)개 저장소 확인")
        }
    }

    private func startGitHubScanIfNeeded(id: UUID) {
        guard githubTask == nil,
              githubLastCheckedAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        githubIsLoading = true
        githubLastCheckedAt = Date()
        githubTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                JarvisGitHubRemoteScanner.scan()
            }
            let snapshot = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, !Task.isCancelled, self.isVisible, self.revision == id else { return }
            self.githubSnapshot = snapshot
            self.githubIsLoading = false
            self.githubTask = nil
            self.recordCheck("GitHub 계정 API", success: snapshot.error == nil,
                             detail: snapshot.error ?? "\(snapshot.repositories.count)개 원격 저장소 확인")
        }
    }

    private func startVercelScanIfNeeded(id: UUID) {
        guard vercelTask == nil,
              vercelLastCheckedAt.map({ Date().timeIntervalSince($0) > 120 }) ?? true else { return }
        vercelIsLoading = true
        vercelLastCheckedAt = Date()
        vercelTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                JarvisVercelRemoteScanner.scan()
            }
            let snapshot = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, !Task.isCancelled, self.isVisible, self.revision == id else { return }
            self.vercelSnapshot = snapshot
            self.vercelIsLoading = false
            self.vercelTask = nil
            self.recordCheck("Vercel CLI", success: snapshot.error == nil,
                             detail: snapshot.error ?? "\(snapshot.projects.count)개 프로젝트 · 최근 배포 \(snapshot.deployments.count)건")
        }
    }

    func hide() -> String {
        revision = UUID()
        pollingTask?.cancel()
        pollingTask = nil
        gitTask?.cancel()
        gitTask = nil
        gitIsLoading = false
        githubTask?.cancel()
        githubTask = nil
        githubIsLoading = false
        vercelTask?.cancel()
        vercelTask = nil
        vercelIsLoading = false
        isVisible = false
        isLoading = false
        isRefreshing = false
        return "실시간 대시보드를 닫았습니다. 갱신도 중단했습니다."
    }

    func cancel() {
        _ = hide()
        session.invalidateAndCancel()
    }
}
