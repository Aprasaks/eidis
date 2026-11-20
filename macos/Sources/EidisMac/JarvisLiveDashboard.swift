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
        let dashboard = text.contains("대시보드") || text.contains("현황판") || text.contains("통계")
        let project = ["프로젝트", "작업현황", "할일", "해야할일", "진행상황"].contains { text.contains($0) }
        let knowledge = ["보관함", "저장자료", "저장한자료", "내자료", "지식", "기억통계", "자료분석"].contains { text.contains($0) }
        let system = ["자비스상태", "시스템상태", "서버상태", "ollama상태", "로컬서버", "시스템진단"].contains { text.contains($0) }
        let close = ["닫아", "꺼줘", "숨겨", "치워", "내려", "접어"].contains { text.contains($0) }
        if dashboard && close { return .hide }
        let externalSignals = ["유튜브", "youtube", "뉴스", "날씨", "증시", "주가", "주식", "stock",
                               "깃허브", "github", "인스타", "instagram", "threads", "코인", "환율", "외부"]
        let external = externalSignals.contains { text.contains($0) }
        if dashboard && external { return .unavailable }
        let showing = ["보여", "띄워", "열어", "알려", "확인", "분석", "현황", "상태", "통계", "갱신", "새로고침"].contains { text.contains($0) }
        guard showing else { return nil }
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
            let general = ["전체", "종합", "통합", "내현황", "자비스대시보드", "실시간대시보드", "대시보드띄워", "대시보드보여", "현황판띄워"].contains {
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
        var success = true
        if needsProjects {
            do {
                let reply: WorkProjectsReply = try await fetch("/api/projects")
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                projects = reply.items
                projectsReady = true
            } catch {
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                success = false
                projects = []
                projectsReady = false
            }
        }
        if needsVault {
            do {
                let reply: LiveVaultReply = try await fetch("/api/vault?limit=12")
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                vaultTotal = reply.total
                vaultCounts = reply.counts
                recentItems = Array(reply.items.prefix(6))
            } catch {
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                success = false
                vaultTotal = nil
                vaultCounts = [:]
                recentItems = []
            }
        }
        if needsStatus {
            do {
                let diagnostics: LiveDiagnosticsReply = try await fetch("/api/diagnostics")
                let status: LiveStatusReply = try await fetch("/api/status")
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                databaseStatus = diagnostics.database.status
                profileCount = status.profileCount
            } catch {
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                success = false
                databaseStatus = nil
                profileCount = nil
            }
            do {
                let ollama: LiveOllamaReply = try await fetch("/api/version", port: 11434)
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                ollamaVersion = ollama.version
            } catch {
                guard isVisible && revision == id && !Task.isCancelled else { return false }
                ollamaVersion = nil // A disconnected Ollama is a real status, not invented data.
            }
            ollamaChecked = true
        }
        guard isVisible && revision == id && !Task.isCancelled else { return false }
        errorText = success ? nil : "일부 로컬 자료에 연결되지 않았습니다. 해당 값은 표시하지 않습니다."
        refreshedAt = Date()
        isLoading = false
        isRefreshing = false
        return success
    }

    func hide() -> String {
        revision = UUID()
        pollingTask?.cancel()
        pollingTask = nil
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
