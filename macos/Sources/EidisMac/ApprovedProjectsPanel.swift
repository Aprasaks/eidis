import Foundation
import SwiftUI

// Project status is read from the existing loopback server.
// External GitHub access happens only after the user confirms a single proposal.
struct WorkProject: Decodable, Identifiable {
    let id: Int
    let name: String
    let goal: String
    let repoFullName: String
    let tasks: [WorkTask]
    let taskCounts: WorkCounts
    let lastCheck: WorkGitHubEvidence?
}

struct WorkTask: Decodable, Identifiable {
    let id: Int
    let title: String
    let status: String
}

struct WorkCounts: Decodable {
    let todo: Int
    let doing: Int
    let blocked: Int
    let done: Int
}

struct WorkGitHubEvidence: Decodable {
    let branch: String
    let headSha: String
    let workflowState: String
    let workflowConclusion: String
    let checkedAt: String
}

struct WorkProjectsReply: Decodable { let items: [WorkProject] }
struct WorkCheckReceipt: Decodable {
    let id: Int
    let status: String
    let outcome: String
    let projectId: Int
}
struct WorkCheckReply: Decodable {
    let project: WorkProject
    let receipt: WorkCheckReceipt
}
struct WorkErrorReply: Decodable { let error: String }

struct WorkCheckProposal: Identifiable, Equatable {
    let projectId: Int
    let projectName: String
    let repository: String
    let id = UUID()

    static func forProject(_ project: WorkProject) -> WorkCheckProposal? {
        guard !project.repoFullName.isEmpty else { return nil }
        return WorkCheckProposal(projectId: project.id, projectName: project.name,
                                 repository: project.repoFullName)
    }

    var explanation: String {
        "GitHub 공개 API에서 \(repository)의 기본 브랜치 최신 HEAD와 그 커밋에 맞는 Workflow 기록을 한 번 읽습니다. 기록은 로컬 프로젝트 DB에 남습니다. 파일 변경·푸시·배포·삭제는 하지 않습니다."
    }
}

@MainActor
final class ApprovedWorkModel: ObservableObject {
    @Published private(set) var projects: [WorkProject] = []
    @Published private(set) var busy = false
    @Published private(set) var status = "로컬 프로젝트를 불러오지 않았습니다."
    @Published private(set) var lastReceipt: WorkCheckReceipt?

    private let base = URL(string: "http://127.0.0.1:8765")!
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func fetch<T: Decodable>(_ path: String, body: Data? = nil) async throws -> T {
        guard path == "/api/projects" || path == "/api/projects/github/check",
              let url = URL(string: path, relativeTo: base)?.absoluteURL,
              url.host == "127.0.0.1", url.port == 8765 else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = body == nil ? 5 : 28
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            let reported = try? decoder.decode(WorkErrorReply.self, from: data)
            throw WorkActionError.server(reported?.error ?? "로컬 서버 오류 HTTP \(http.statusCode)")
        }
        return try decoder.decode(T.self, from: data)
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let result: WorkProjectsReply = try await fetch("/api/projects")
            projects = result.items
            status = "프로젝트 \(result.items.count)개를 로컬 DB에서 읽었습니다. GitHub는 조회하지 않았습니다."
        } catch {
            status = "로컬 프로젝트 확인 실패: \(error.localizedDescription)"
        }
    }

    func runApprovedCheck(_ proposal: WorkCheckProposal) async {
        guard !busy else { return }
        busy = true
        lastReceipt = nil
        defer { busy = false }
        do {
            // Fresh local read so an edited project cannot silently retarget
            // the already approved GitHub repository.
            let current: WorkProjectsReply = try await fetch("/api/projects")
            guard current.items.contains(where: {
                $0.id == proposal.projectId &&
                $0.name == proposal.projectName &&
                $0.repoFullName == proposal.repository
            }) else {
                throw WorkActionError.server("프로젝트 정보가 승인 후 변경됐습니다. 다시 제안을 만드세요.")
            }
            let body = try JSONSerialization.data(withJSONObject: [
                "project_id": proposal.projectId
            ])
            let response: WorkCheckReply = try await fetch("/api/projects/github/check", body: body)
            guard response.project.id == proposal.projectId,
                  response.project.repoFullName == proposal.repository,
                  response.receipt.projectId == proposal.projectId,
                  response.receipt.status == "completed" else {
                throw WorkActionError.server("서버의 실행 결과가 승인한 작업과 일치하지 않습니다.")
            }
            lastReceipt = response.receipt
            if let check = response.project.lastCheck {
                let workflow = check.workflowState == "unavailable"
                    ? "현재 HEAD에 일치하는 Workflow 증거 없음"
                    : "Workflow \(check.workflowState)/\(check.workflowConclusion)"
                status = "읽기 전용 실행 확인 · 영수증 #\(response.receipt.id) · \(proposal.repository) \(check.branch) @ \(check.headSha.prefix(10)) · \(workflow) · 확인 시각 \(check.checkedAt). AWS 배포 완료 여부는 검증하지 않았습니다."
            } else {
                status = "GitHub 호출은 기록됐지만 최신 커밋 결과를 확인하지 못했습니다."
            }
            // A failed local UI refresh cannot turn a completed GitHub read
            // into an apparent execution failure or trigger a retry.
            if let latest: WorkProjectsReply = try? await fetch("/api/projects") {
                projects = latest.items
            } else {
                status += " 로컬 목록 갱신은 실패했습니다. 실행은 자동 재시도하지 않습니다."
            }
        } catch {
            status = "GitHub 읽기 작업 실패 또는 상태 미확인: \(error.localizedDescription). 자동 재시도하지 않았습니다."
        }
    }
}

enum WorkActionError: LocalizedError {
    case server(String)
    var errorDescription: String? {
        switch self { case .server(let message): message }
    }
}

struct ApprovedProjectsPanel: View {
    @StateObject private var work = ApprovedWorkModel()
    @State private var selectedProjectId = 0
    @State private var proposal: WorkCheckProposal?
    @State private var confirmationVisible = false

    private var selected: WorkProject? {
        work.projects.first(where: { $0.id == selectedProjectId })
    }

    private func load() async {
        await work.refresh()
        if !work.projects.contains(where: { $0.id == selectedProjectId }) {
            selectedProjectId = work.projects.first?.id ?? 0
            proposal = nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("자비스의 업무 실행실")
                            .font(.title3.weight(.medium))
                        Text("프로젝트 기록 → 작업 제안 → 사용자 승인 → 읽기 전용 실행 → 근거 보고")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("로컬 기록 새로 읽기") {
                        proposal = nil
                        Task { await load() }
                    }
                    .disabled(work.busy)
                }
                HStack {
                    Picker("프로젝트", selection: $selectedProjectId) {
                        if work.projects.isEmpty { Text("등록된 프로젝트 없음").tag(0) }
                        ForEach(work.projects) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                    .frame(maxWidth: 470)
                    .onChange(of: selectedProjectId) { _, _ in proposal = nil }
                    Spacer()
                }
                if let selected {
                    GroupBox("프로젝트 상태 · 로컬에 저장된 기록") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(selected.goal.isEmpty ? "목표 미입력" : selected.goal)
                                .font(.callout)
                            Text("예정 \(selected.taskCounts.todo) · 진행 \(selected.taskCounts.doing) · 막힘 \(selected.taskCounts.blocked) · 완료 \(selected.taskCounts.done)")
                            if let last = selected.lastCheck {
                                Text("마지막 GitHub 조회: \(last.checkedAt)")
                                Text("\(last.branch) @ \(last.headSha.prefix(12)) · Workflow \(last.workflowState)/\(last.workflowConclusion)")
                            } else {
                                Text("GitHub 조회 기록 없음")
                            }
                            ForEach(selected.tasks.prefix(7)) { task in
                                Text("• \(task.title) [\(task.status)]")
                                    .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("1단계 · 외부 작업 제안") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("허용 작업: 공개 GitHub HEAD 및 Workflow 읽기")
                                .font(.subheadline.weight(.medium))
                            Text("실제 조회는 자동 실행되지 않습니다. 각 요청은 별도 승인 후 한 번만 실행됩니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("읽기 전용 작업 제안 만들기") {
                                proposal = WorkCheckProposal.forProject(selected)
                            }
                            .disabled(selected.repoFullName.isEmpty || work.busy)
                            if let proposal {
                                Text("대상: \(proposal.projectName)")
                                Text(proposal.explanation)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                Button("이 작업 승인 화면 열기") {
                                    confirmationVisible = true
                                }
                                .disabled(work.busy)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("프로젝트를 선택하세요. 기존 자비스 작업 공간의 프로젝트 화면에서 등록할 수 있습니다.")
                        .foregroundStyle(.secondary)
                }
                if work.busy { ProgressView("조회 중…") }
                GroupBox("실행 결과 및 영수증") {
                    Text(work.status)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("실행 도구는 GitHub 공개 저장소 읽기만 지원합니다. 프로젝트 작업 완료 판단, 코드 수정, AWS 배포나 변경은 하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .task { await load() }
        .confirmationDialog("이 공개 GitHub 조회를 한 번 승인할까요?",
                            isPresented: $confirmationVisible,
                            titleVisibility: .visible) {
            Button("승인하고 공개 GitHub 1회 조회") {
                guard let proposal else { return }
                self.proposal = nil
                Task { await work.runApprovedCheck(proposal) }
            }
            Button("취소", role: .cancel) { proposal = nil }
        } message: {
            Text(proposal?.explanation ?? "제안이 없습니다.")
        }
    }
}
