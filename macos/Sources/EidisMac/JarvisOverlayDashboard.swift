import Foundation
import SwiftUI

/// Recognize only explicit read-only dashboard intents. Other utterances go to Qwen.
/// No mutation, network search, or LLM is involved in command routing.
enum JarvisDashboardIntent: Equatable {
    case show, hide

    static func parse(_ text: String) -> Self? {
        let normalized = text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
        let dashboard = normalized.contains("대시보드") || normalized.contains("현황판")
        let work = normalized.contains("작업") || normalized.contains("프로젝트") ||
            normalized.contains("할일") || normalized.contains("해야할일")
        guard dashboard || work else { return nil }
        let hide = ["닫아", "닫기", "꺼", "숨겨", "감춰", "치워", "없애"].contains { normalized.contains($0) }
        if hide { return .hide }
        let open = ["보여", "띄워", "열어", "알려", "확인", "현황", "목록", "정리"].contains {
            normalized.contains($0)
        }
        return open ? .show : nil
    }
}

/// The same read-only model as the existing native Work tab, fetched on demand.
/// The database is never modified or replaced by generated sample values.
@MainActor
final class JarvisOverlayDashboard: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var isLoading = false
    @Published private(set) var projects: [WorkProject] = []
    @Published private(set) var errorText: String?
    @Published private(set) var refreshedAt: Date?

    private let session: URLSession
    private var revision = UUID()

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        session = URLSession(configuration: config)
    }

    var totalTodo: Int { projects.reduce(0) { $0 + $1.taskCounts.todo } }
    var totalDoing: Int { projects.reduce(0) { $0 + $1.taskCounts.doing } }
    var totalBlocked: Int { projects.reduce(0) { $0 + $1.taskCounts.blocked } }
    var totalDone: Int { projects.reduce(0) { $0 + $1.taskCounts.done } }

    func show() async -> String {
        isVisible = true
        isLoading = true
        errorText = nil
        refreshedAt = nil
        projects = [] // never display outdated numbers as fresh
        let current = UUID()
        revision = current
        guard let url = URL(string: "http://127.0.0.1:8765/api/projects") else {
            isLoading = false
            errorText = "로컬 서버 주소를 사용할 수 없습니다."
            return errorText!
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 6
        do {
            let (data, response) = try await session.data(for: request)
            guard current == revision, !Task.isCancelled else { return "" }
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else {
                throw URLError(.badServerResponse)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(WorkProjectsReply.self, from: data)
            guard current == revision, !Task.isCancelled else { return "" }
            projects = result.items
            refreshedAt = Date()
            isLoading = false
            if projects.isEmpty { return "등록된 프로젝트가 없습니다. 대시보드를 열었습니다." }
            return "작업 현황을 보여드릴게요. 프로젝트 \(projects.count)개, 예정 \(totalTodo)건, 진행 \(totalDoing)건, 막힘 \(totalBlocked)건, 완료 \(totalDone)건입니다."
        } catch {
            guard current == revision, !Task.isCancelled else { return "" }
            isLoading = false
            projects = []
            errorText = "로컬 프로젝트 기록을 읽지 못했습니다. 서버 연결 상태를 확인해 주세요."
            return errorText!
        }
    }

    func hide() -> String {
        revision = UUID()
        isVisible = false
        isLoading = false
        projects = []
        refreshedAt = nil
        errorText = nil
        return "작업 대시보드를 닫았습니다."
    }

    func cancel() {
        _ = hide()
        session.invalidateAndCancel()
    }
}
