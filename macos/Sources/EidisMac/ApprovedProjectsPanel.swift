import AppKit
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

    // Derived only from locally saved user task states, not GitHub evidence.
    var nextTasks: [WorkTask] {
        Array((Array(tasks.filter { $0.status == "doing" }.reversed()) +
               Array(tasks.filter { $0.status == "todo" }.reversed())).prefix(5))
    }

    var blockedTasks: [WorkTask] {
        tasks.filter { $0.status == "blocked" }
    }
}

enum WorkTaskState: String, CaseIterable, Identifiable {
    case todo, doing, blocked, done
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todo: "예정"
        case .doing: "진행"
        case .blocked: "막힘"
        case .done: "완료"
        }
    }
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
struct WorkTaskAddedReply: Decodable { let task: WorkTask }
struct WorkProjectUpdatedReply: Decodable { let project: WorkProject }
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

/// A local task state transition proposed by the user. Creating the proposal
/// never writes to SQLite, contacts GitHub or opens an external application.
struct WorkTaskStartProposal: Identifiable {
    let id = UUID()
    let projectId: Int
    let projectName: String
    let repository: String
    let taskId: Int
    let taskTitle: String
    let createdAt: Date

    static func forTask(_ task: WorkTask, in project: WorkProject,
                        now: Date = Date()) -> WorkTaskStartProposal? {
        guard task.id > 0, task.status == "todo",
              project.tasks.contains(where: {
                  $0.id == task.id && $0.title == task.title && $0.status == "todo"
              }) else { return nil }
        return WorkTaskStartProposal(
            projectId: project.id, projectName: project.name,
            repository: project.repoFullName, taskId: task.id,
            taskTitle: task.title, createdAt: now)
    }

    var explanation: String {
        "프로젝트: \(projectName)\n작업: \(taskTitle)\n" +
        "이 한 작업의 로컬 기록만 ‘예정’에서 ‘진행’으로 변경합니다. " +
        "실제 개발·완료·배포를 의미하지 않습니다. " +
        "기록 성공 후 Finder/GitHub 열기 제안만 준비하며, 실제 열기는 별도 승인이 필요합니다."
    }
}

@MainActor
final class ApprovedWorkModel: ObservableObject {
    @Published private(set) var projects: [WorkProject] = []
    @Published private(set) var busy = false
    @Published private(set) var status = "로컬 프로젝트를 불러오지 않았습니다."
    @Published private(set) var lastRefreshSucceeded = false
    @Published private(set) var lastReceipt: WorkCheckReceipt?
    @Published private(set) var localEvidence: [Int: LocalGitEvidence] = [:]
    @Published private(set) var localMessages: [Int: String] = [:]
    @Published private(set) var workspaceReceipt: JarvisWorkspaceReceipt?
    @Published private(set) var taskNoteReceipt: JarvisTaskNoteReceipt?
    @Published private(set) var savedNotes: [JarvisSavedNote] = []
    @Published private(set) var savedNoteText = ""
    @Published private(set) var savedNoteFilename = ""
    @Published private(set) var savedNoteMessage = ""
    @Published private(set) var revisionReceipt: JarvisTaskNoteReceipt?
    @Published private(set) var savedNoteProjectId = 0
    @Published private(set) var savedNoteTaskId = 0

    /// Only called from a user-confirmed one-shot dialog.
    func openApprovedWorkspace(_ proposal: JarvisWorkspaceProposal) {
        guard !busy else { return }
        let project = projects.first(where: { $0.id == proposal.projectId })
        let receipt = JarvisWorkspaceResume.perform(
            proposal: proposal, currentProject: project,
            currentLinkedFolder: localFolder(projectId: proposal.projectId),
            opener: { NSWorkspace.shared.open($0) })
        workspaceReceipt = receipt
        // A request accepted by macOS is not proof that Finder or a webpage loaded.
        status = receipt.summary
    }

    private func localFolderKey(_ id: Int) -> String {
        "jarvis.work.local-git-folder.\(id)"
    }

    func localFolder(projectId: Int) -> String? {
        UserDefaults.standard.string(forKey: localFolderKey(projectId))
    }

    func disconnectLocalFolder(projectId: Int) {
        guard !busy else { return }
        UserDefaults.standard.removeObject(forKey: localFolderKey(projectId))
        localEvidence.removeValue(forKey: projectId)
        localMessages[projectId] = "로컬 Git 폴더 연결을 해제했습니다. 실제 파일이나 저장소는 변경하지 않았습니다."
    }

    func connectLocalFolder(projectId: Int, url: URL) async {
        guard !busy, projects.contains(where: { $0.id == projectId }) else { return }
        busy = true
        localEvidence.removeValue(forKey: projectId)
        defer { busy = false }
        do {
            let evidence = try await Task.detached(priority: .userInitiated) {
                try LocalGitInspector.inspect(folderURL: url)
            }.value
            guard projects.contains(where: { $0.id == projectId }) else {
                throw WorkActionError.server("대상 프로젝트가 변경되어 연결하지 않았습니다.")
            }
            UserDefaults.standard.set(evidence.rootPath, forKey: localFolderKey(projectId))
            localEvidence[projectId] = evidence
            localMessages[projectId] = "사용자가 선택한 Git 폴더를 연결하고 한 번 읽었습니다. 파일 수정이나 외부 전송은 없었습니다."
        } catch {
            localMessages[projectId] = "폴더 연결 실패: \(error.localizedDescription). 기존 연결은 그대로 보존했습니다."
        }
    }

    func inspectLocalFolder(projectId: Int) async {
        guard !busy, projects.contains(where: { $0.id == projectId }),
              let saved = localFolder(projectId: projectId) else { return }
        busy = true
        localEvidence.removeValue(forKey: projectId)
        defer { busy = false }
        do {
            let evidence = try await Task.detached(priority: .userInitiated) {
                try LocalGitInspector.inspect(folderURL: URL(fileURLWithPath: saved))
            }.value
            guard projects.contains(where: { $0.id == projectId }),
                  localFolder(projectId: projectId) == saved else {
                throw WorkActionError.server("프로젝트나 연결 경로가 변경돼 결과를 적용하지 않았습니다.")
            }
            localEvidence[projectId] = evidence
            localMessages[projectId] = "사용자 요청으로 로컬 Git 상태를 한 번 확인했습니다. 파일 수정·GitHub 조회·DB 변경 없음."
        } catch {
            localMessages[projectId] = "로컬 Git 조회 실패: \(error.localizedDescription). 이전 결과를 현재 상태로 표시하지 않습니다."
        }
    }

    private let base = URL(string: "http://127.0.0.1:8765")!
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func fetch<T: Decodable>(_ path: String, body: Data? = nil) async throws -> T {
        guard ["/api/projects", "/api/projects/github/check",
               "/api/projects/task", "/api/projects/status"].contains(path),
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
        lastRefreshSucceeded = false
        defer { busy = false }
        do {
            let result: WorkProjectsReply = try await fetch("/api/projects")
            projects = result.items
            lastRefreshSucceeded = true
            status = "프로젝트 \(result.items.count)개를 로컬 DB에서 읽었습니다. GitHub는 조회하지 않았습니다."
        } catch {
            status = "로컬 프로젝트 확인 실패: \(error.localizedDescription)"
        }
    }

    /// A click in the native Work tab is a deliberate local task write.
    /// No GitHub call, automation, or inferred completion is involved.
    func addTask(projectId: Int, title: String) async -> Bool {
        guard !busy else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(trimmed.count),
              projects.contains(where: { $0.id == projectId }) else {
            status = "유효한 프로젝트와 1~200자 작업 이름을 지정해 주세요."
            return false
        }
        busy = true
        defer { busy = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: [
                "project_id": projectId, "title": trimmed
            ])
            let result: WorkTaskAddedReply = try await fetch("/api/projects/task", body: body)
            guard result.task.id > 0, result.task.title == trimmed,
                  result.task.status == "todo" else {
                throw WorkActionError.server("추가 응답을 확인하지 못했습니다. 로컬 목록에서 실제 저장 여부를 확인해 주세요.")
            }
            status = "작업 #\(result.task.id) 저장 확인: \(trimmed) · 예정. GitHub 조회나 작업 실행은 하지 않았습니다."
            if let latest: WorkProjectsReply = try? await fetch("/api/projects") {
                projects = latest.items
            } else {
                status += " 목록 갱신에 실패했으니 로컬 기록 새로 읽기를 눌러 주세요."
            }
            return true
        } catch {
            status = "작업 저장 실패 또는 상태 미확인: \(error.localizedDescription). 중복 방지를 위해 자동 재시도하지 않습니다."
            return false
        }
    }

    func updateTask(projectId: Int, taskId: Int, next: WorkTaskState) async {
        guard !busy else { return }
        guard let project = projects.first(where: { $0.id == projectId }),
              let task = project.tasks.first(where: { $0.id == taskId }) else {
            status = "작업을 찾지 못했습니다. 로컬 기록을 새로 읽어 주세요."
            return
        }
        guard task.status != next.rawValue else {
            status = "이미 같은 상태로 기록되어 있습니다."
            return
        }
        busy = true
        defer { busy = false }
        do {
            // Server explicitly records actor=user and the prior/new status.
            let body = try JSONSerialization.data(withJSONObject: [
                "project_id": projectId, "task_id": taskId, "status": next.rawValue
            ])
            let result: WorkProjectUpdatedReply = try await fetch("/api/projects/status", body: body)
            guard result.project.id == projectId,
                  result.project.tasks.contains(where: {
                      $0.id == taskId && $0.status == next.rawValue
                  }) else {
                throw WorkActionError.server("상태 변경 응답이 요청과 일치하지 않습니다.")
            }
            if let index = projects.firstIndex(where: { $0.id == projectId }) {
                projects[index] = result.project
            }
            status = "사용자 기록 변경 완료: \(task.title) → \(next.label). 실제 코드 작업·배포가 완료됐다는 검증은 아닙니다."
        } catch {
            status = "상태 변경 실패 또는 미확인: \(error.localizedDescription). 자동 재시도하지 않습니다."
        }
    }

    /// Re-read before changing any task: the approved project, task title and
    /// original TODO state must still match. Never retry an uncertain write.
    func beginApprovedTask(_ proposal: WorkTaskStartProposal) async -> Bool {
        guard !busy else { return false }
        let age = Date().timeIntervalSince(proposal.createdAt)
        guard (0...120).contains(age) else {
            status = "작업 시작 승인이 만료됐습니다. 제안을 다시 만들어 주세요."
            return false
        }
        busy = true
        defer { busy = false }
        do {
            let current: WorkProjectsReply = try await fetch("/api/projects")
            guard let project = current.items.first(where: {
                $0.id == proposal.projectId &&
                $0.name == proposal.projectName &&
                $0.repoFullName == proposal.repository
            }),
                  project.tasks.contains(where: {
                      $0.id == proposal.taskId &&
                      $0.title == proposal.taskTitle &&
                      $0.status == "todo"
                  }) else {
                throw WorkActionError.server(
                    "대상 프로젝트나 작업 상태가 승인 이후 변경됐습니다. 상태를 갱신하지 않았습니다.")
            }
            let body = try JSONSerialization.data(withJSONObject: [
                "project_id": proposal.projectId, "task_id": proposal.taskId,
                "status": "doing"
            ])
            let result: WorkProjectUpdatedReply = try await fetch(
                "/api/projects/status", body: body)
            guard result.project.id == proposal.projectId,
                  result.project.name == proposal.projectName,
                  result.project.repoFullName == proposal.repository,
                  result.project.tasks.contains(where: {
                      $0.id == proposal.taskId &&
                      $0.title == proposal.taskTitle &&
                      $0.status == "doing"
                  }) else {
                throw WorkActionError.server("서버 응답을 확인하지 못했습니다. 자동 재시도하지 않습니다.")
            }
            if let index = projects.firstIndex(where: { $0.id == proposal.projectId }) {
                projects[index] = result.project
            } else {
                projects = current.items.map {
                    $0.id == proposal.projectId ? result.project : $0
                }
            }
            status = "승인한 작업을 진행으로 기록했습니다: \(proposal.taskTitle). 실제 개발·배포 완료는 아닙니다. 아래 작업 공간 제안은 별도로 승인해야 열립니다."
            return true
        } catch {
            status = "작업 시작 실패 또는 미확인: \(error.localizedDescription). 자동 재시도하지 않습니다. 로컬 기록을 새로 확인해 주세요."
            return false
        }
    }

    /// Saves a single immutable preview after an explicit user approval.
    /// A fresh API read and the unchanged linked folder are required.
    func saveApprovedTaskNote(_ proposal: JarvisTaskNoteProposal) async -> Bool {
        guard !busy else { return false }
        taskNoteReceipt = nil
        busy = true
        defer { busy = false }
        do {
            let latest: WorkProjectsReply = try await fetch("/api/projects")
            let project = latest.items.first(where: {
                $0.id == proposal.projectId &&
                $0.name == proposal.projectName &&
                $0.repoFullName == proposal.repository
            })
            let folder = localFolder(projectId: proposal.projectId)
            let receipt = try await Task.detached(priority: .userInitiated) {
                try JarvisTaskNote.save(
                    proposal, currentProject: project,
                    currentLinkedFolder: folder)
            }.value
            taskNoteReceipt = receipt
            status = receipt.summary
            return true
        } catch {
            status = "실행 메모 저장 실패 또는 미확인: \(error.localizedDescription). 다른 경로에 자동 재시도하지 않습니다."
            return false
        }
    }

    /// Only reads regular task-specific notes under a manually linked Git
    /// root. Never changes a file or accesses unrelated project data.
    func loadSavedNotes(projectId: Int, taskId: Int) async {
        guard !busy else { return }
        savedNotes = []
        savedNoteText = ""
        savedNoteFilename = ""
        savedNoteProjectId = 0
        savedNoteTaskId = 0
        guard projects.first(where: { $0.id == projectId })?
            .tasks.contains(where: { $0.id == taskId }) == true,
              let linked = localFolder(projectId: projectId) else {
            savedNoteMessage = "프로젝트 작업과 연결된 Git 폴더를 먼저 확인해 주세요."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let files = try await Task.detached(priority: .userInitiated) {
                try JarvisNoteLibrary.list(taskId: taskId, linkedFolder: linked)
            }.value
            guard projects.first(where: { $0.id == projectId })?
                .tasks.contains(where: { $0.id == taskId }) == true,
                localFolder(projectId: projectId) == linked else {
                throw JarvisNoteLibraryError.invalidFolder
            }
            savedNotes = files
            savedNoteProjectId = projectId
            savedNoteTaskId = taskId
            savedNoteMessage = files.isEmpty
                ? "이 작업에서 저장된 메모를 찾지 못했습니다."
                : "이 작업의 저장된 메모 \\(files.count)개를 목록에 표시했습니다. 내용을 보려면 파일을 직접 선택하세요."
        } catch {
            savedNoteMessage = "기존 메모 목록 읽기 실패: \\(error.localizedDescription)"
        }
    }

    func saveApprovedRevision(_ proposal: JarvisNoteRevisionProposal) async -> Bool {
        guard !busy else { return false }
        revisionReceipt = nil
        busy = true
        defer { busy = false }
        do {
            let latest: WorkProjectsReply = try await fetch("/api/projects")
            let project = latest.items.first(where: {
                $0.id == proposal.projectId &&
                $0.name == proposal.projectName &&
                $0.repoFullName == proposal.repository
            })
            let folder = localFolder(projectId: proposal.projectId)
            let receipt = try await Task.detached(priority: .userInitiated) {
                try JarvisNoteRevision.save(
                    proposal, currentProject: project,
                    currentLinkedFolder: folder)
            }.value
            revisionReceipt = receipt
            status = "원본을 보존하고 수정본을 새 파일로 저장했습니다. \\(receipt.summary)"
            return true
        } catch {
            status = "수정본 저장 실패 또는 미확인: \\(error.localizedDescription) 자동 재시도하지 않습니다."
            return false
        }
    }

    func readSavedNote(projectId: Int, taskId: Int, filename: String) async {
        guard !busy, savedNoteProjectId == projectId,
              savedNoteTaskId == taskId,
              savedNotes.contains(where: { $0.filename == filename }),
              let linked = localFolder(projectId: projectId) else { return }
        busy = true
        defer { busy = false }
        savedNoteText = ""
        savedNoteFilename = ""
        do {
            let content = try await Task.detached(priority: .userInitiated) {
                try JarvisNoteLibrary.read(
                    filename: filename, taskId: taskId, linkedFolder: linked)
            }.value
            guard savedNoteProjectId == projectId,
                  savedNoteTaskId == taskId,
                  localFolder(projectId: projectId) == linked else {
                throw JarvisNoteLibraryError.invalidFolder
            }
            savedNoteText = content
            savedNoteFilename = filename
            savedNoteMessage = "읽기 전용으로 \\(filename)을 열었습니다. 내용을 수정하지 않았습니다."
        } catch {
            savedNoteMessage = "메모 읽기 실패: \\(error.localizedDescription)"
        }
    }

    func clearSavedNoteSelection() {
        savedNotes = []
        savedNoteText = ""
        savedNoteFilename = ""
        savedNoteMessage = ""
        savedNoteProjectId = 0
        savedNoteTaskId = 0
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
    @ObservedObject var work: ApprovedWorkModel
    let requestedWorkspace: JarvisWorkspaceCommand?
    @State private var selectedProjectId = 0
    @State private var localPlanBusy = false
    @State private var localPlan: JarvisLocalPlan?
    @State private var localPlanMessage = "아직 제안하지 않았습니다."

    init(work: ApprovedWorkModel, requestedWorkspace: JarvisWorkspaceCommand? = nil) {
        self.work = work
        self.requestedWorkspace = requestedWorkspace
    }
    @State private var proposal: WorkCheckProposal?
    @State private var confirmationVisible = false
    @State private var newTaskTitle = ""
    @State private var taskStartProposal: WorkTaskStartProposal?
    @State private var taskStartConfirmationVisible = false
    @State private var taskWorkspaceRequest: JarvisWorkspaceCommand?
    @State private var taskNoteTaskId: Int?
    @State private var taskNoteDraft = ""
    @State private var taskNoteProposal: JarvisTaskNoteProposal?
    @State private var taskNoteConfirmationVisible = false
    @State private var revisionSourceFilename = ""
    @State private var revisionSourceText = ""
    @State private var revisionSourceProjectId = 0
    @State private var revisionSourceTaskId = 0
    @State private var revisionDraft = ""
    @State private var revisionProposal: JarvisNoteRevisionProposal?
    @State private var revisionConfirmationVisible = false

    private var selected: WorkProject? {
        work.projects.first(where: { $0.id == selectedProjectId })
    }

    private func suggestLocalNextStep(for project: WorkProject) {
        guard !localPlanBusy, !work.busy else { return }
        localPlan = nil
        localPlanMessage = "기기 내 AI가 기록을 읽고 있습니다. 외부 API는 호출하지 않습니다."
        let context: JarvisPlanningSnapshot
        do {
            context = try JarvisLocalPlanning.snapshot(
                project: project,
                localFolderConnected: work.localFolder(projectId: project.id) != nil,
                localEvidence: work.localEvidence[project.id],
                openedNote: work.savedNoteText,
                openedNoteProjectId: work.savedNoteProjectId,
                openedNoteTaskId: work.savedNoteTaskId
            )
        } catch {
            localPlanMessage = error.localizedDescription
            return
        }
        localPlanBusy = true
        Task {
            defer { localPlanBusy = false }
            do {
                let generated = try await JarvisLocalPlanning.suggest(from: context)
                guard selectedProjectId == context.projectId,
                      let current = selected,
                      context.stillMatches(current) else {
                    localPlanMessage = "프로젝트/작업 정보가 변경돼 이전 AI 제안을 표시하지 않았습니다."
                    return
                }
                localPlan = generated
                localPlanMessage = "기기 내 Apple 모델의 제안입니다. 실제 코드나 배포 상태를 새로 검증하지 않았습니다."
            } catch {
                localPlanMessage = error.localizedDescription
            }
        }
    }

    private func chooseLocalFolder(projectId: Int) {
        guard !work.busy else { return }
        let picker = NSOpenPanel()
        picker.title = "직접 확인할 Git 프로젝트 폴더 선택"
        picker.message = "선택한 저장소만 로컬에서 읽습니다. 코드 수정·GitHub 전송은 하지 않습니다."
        picker.prompt = "이 폴더 연결"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.canCreateDirectories = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        Task { await work.connectLocalFolder(projectId: projectId, url: url) }
    }

    private func applyRequestedProject() {
        guard let request = requestedWorkspace,
              work.projects.contains(where: {
                  $0.id == request.projectId &&
                  $0.name == request.projectName &&
                  $0.repoFullName == request.repository
              }) else { return }
        selectedProjectId = request.projectId
    }

    private func load() async {
        await work.refresh()
        if !work.projects.contains(where: { $0.id == selectedProjectId }) {
            selectedProjectId = work.projects.first?.id ?? 0
            proposal = nil
        }
        applyRequestedProject()
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
                    .onChange(of: selectedProjectId) { _, _ in
                        localPlan = nil
                        localPlanMessage = "프로젝트가 바뀌어 이전 제안을 지웠습니다."
                        proposal = nil
                        taskStartProposal = nil
                        taskWorkspaceRequest = nil
                        taskNoteTaskId = nil
                        taskNoteDraft = ""
                        taskNoteProposal = nil
                        revisionSourceFilename = ""
                        revisionSourceText = ""
                        revisionDraft = ""
                        revisionProposal = nil
                        work.clearSavedNoteSelection()
                        newTaskTitle = ""
                    }
                    Spacer()
                }
                if let selected {
                    GroupBox("프로젝트 인수인계 · 저장된 사실과 미확인 항목") {
                        VStack(alignment: .leading, spacing: 10) {
                            let summary = JarvisHandoffReport.make(
                                project: selected,
                                localFolderConnected: work.localFolder(projectId: selected.id) != nil,
                                localEvidence: work.localEvidence[selected.id])
                            HStack {
                                Text("지금 이어서 할 일을 한눈에")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Button("인수인계 내용 복사") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(summary.body, forType: .string)
                                }
                                .help("선택한 프로젝트 기록을 클립보드에 복사합니다. 복사된 내용에는 작업 이름과 목표가 포함됩니다.")
                            }
                            Text(summary.body)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("조회 기록은 작성 당시의 스냅샷입니다. 이 요약을 열거나 복사해도 Git·GitHub·AWS 조회나 배포를 실행하지 않습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Mac 기기 내 AI · 다음 작업 한 가지 제안") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center) {
                                Text("저장된 작업·마지막 Git 조회를 바탕으로 다음 확인 행동을 설명합니다.")
                                    .font(.caption)
                                Spacer()
                                Button("AI로 제안받기") {
                                    suggestLocalNextStep(for: selected)
                                }
                                .disabled(localPlanBusy || work.busy || selected.nextTasks.isEmpty)
                            }
                            Text(JarvisLocalPlanning.availabilityDescription())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if localPlanBusy {
                                ProgressView("Mac 로컬 모델이 생각하는 중")
                                    .controlSize(.small)
                            }
                            if let localPlan,
                               localPlan.snapshot.projectId == selected.id,
                               localPlan.snapshot.stillMatches(selected) {
                                Text("고정된 작업: #\(localPlan.snapshot.taskId) · \(localPlan.snapshot.taskTitle)")
                                    .font(.subheadline.weight(.medium))
                                Text("모델에 제공한 자료: 사용자 작업 기록, 이전 인수인계, 마지막 수동 Git 스냅샷" +
                                     (localPlan.snapshot.sourceIncludesOpenedNote
                                      ? ", 이 작업에서 직접 연 메모 일부" : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(localPlan.suggestion)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    Spacer()
                                    Button("AI 제안 복사") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(
                                            "프로젝트: \(localPlan.snapshot.projectName)\n" +
                                            "대상 작업 #\(localPlan.snapshot.taskId): " +
                                            localPlan.snapshot.taskTitle + "\n\n" +
                                            localPlan.suggestion +
                                            "\n\n기기 내 AI 제안. 코드·배포·완료 여부 미검증.",
                                            forType: .string)
                                    }
                                    .help("선택한 작업명과 AI 제안을 클립보드에 복사합니다.")
                                }
                            }
                            Text(localPlanMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("읽기 전용 · 사용자가 버튼을 누를 때만 생성 · 외부 AI API/파일 수정/명령 실행/자동 배포 없음. AI 문장은 제안이며 사실 확인이 아닙니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
                            if !selected.nextTasks.isEmpty {
                                Text("다음 이어 할 일 · 사용자 기록")
                                    .font(.subheadline.weight(.medium))
                                ForEach(selected.nextTasks) { task in
                                    Text("• \(task.title) [\(WorkTaskState(rawValue: task.status)?.label ?? "미상")]")
                                        .font(.caption)
                                }
                                Text("위 순서는 진행 중 → 예정 순서이며, 자동으로 작업을 실행하거나 완료 판정하지 않습니다.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("이어 할 일로 기록된 작업이 없습니다. 아래에서 직접 추가할 수 있어요.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !selected.blockedTasks.isEmpty {
                                Text("막힌 작업 · 사용자 기록")
                                    .font(.subheadline.weight(.medium))
                                ForEach(selected.blockedTasks) { task in
                                    Text("• \(task.title)")
                                        .font(.caption)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("다음 할 일 시작 · 승인 후 로컬 작업 상태 기록") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("최근 등록된 미완료 작업 중 진행 중인 작업을 먼저 보여줍니다. 순서는 자동 우선순위 판단이 아닙니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if selected.nextTasks.isEmpty {
                                Text("시작할 작업이 없습니다. 아래에 예정 작업을 추가해 주세요.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(selected.nextTasks) { task in
                                HStack(alignment: .center, spacing: 10) {
                                    Text(task.title)
                                        .lineLimit(2)
                                    Spacer()
                                    if task.status == "todo" {
                                        Button("이 작업 시작 제안") {
                                            taskStartProposal = WorkTaskStartProposal.forTask(
                                                task, in: selected)
                                        }
                                        .disabled(work.busy)
                                    } else {
                                        Text("진행 중으로 기록됨")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Button("작업 공간 열기 제안") {
                                            taskWorkspaceRequest = JarvisWorkspaceCommand(
                                                projectId: selected.id, projectName: selected.name,
                                                repository: selected.repoFullName,
                                                destination: .choose)
                                        }
                                        .disabled(work.busy)
                                    }
                                    Button("실행 메모") {
                                        taskNoteTaskId = task.id
                                        taskNoteDraft = JarvisTaskNote.initialSteps()
                                        taskNoteProposal = nil
                                        revisionSourceFilename = ""
                                        revisionSourceText = ""
                                        revisionDraft = ""
                                        revisionProposal = nil
                                        work.clearSavedNoteSelection()
                                    }
                                    .disabled(work.busy || work.localFolder(projectId: selected.id) == nil)
                                    Button("저장된 메모") {
                                        taskNoteTaskId = task.id
                                        taskNoteProposal = nil
                                        revisionSourceFilename = ""
                                        revisionSourceText = ""
                                        revisionDraft = ""
                                        revisionProposal = nil
                                        Task {
                                            await work.loadSavedNotes(
                                                projectId: selected.id, taskId: task.id)
                                        }
                                    }
                                    .disabled(work.busy || work.localFolder(projectId: selected.id) == nil)
                                }
                            }
                            if let taskStartProposal {
                                Text(taskStartProposal.explanation)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                Button("시작 승인 화면") {
                                    taskStartConfirmationVisible = true
                                }
                                .disabled(work.busy)
                            }
                            Text("작업 시작을 승인해도 코드 변경·커밋·배포는 자동 실행되지 않습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("내 작업 기록 · 직접 추가하고 상태 변경") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("다음 해야 할 일을 입력하세요", text: $newTaskTitle)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        let title = newTaskTitle
                                        Task {
                                            if await work.addTask(projectId: selected.id, title: title) {
                                                newTaskTitle = ""
                                            }
                                        }
                                    }
                                Button("예정 작업 추가") {
                                    let title = newTaskTitle
                                    Task {
                                        if await work.addTask(projectId: selected.id, title: title) {
                                            newTaskTitle = ""
                                        }
                                    }
                                }
                                .disabled(work.busy ||
                                    newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                    newTaskTitle.count > 200)
                            }
                            if selected.tasks.isEmpty {
                                Text("기록된 작업이 없습니다. 먼저 한 가지를 입력해 주세요.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(selected.tasks) { task in
                                HStack(alignment: .center, spacing: 10) {
                                    Text(task.title)
                                        .font(.callout)
                                        .lineLimit(2)
                                    Spacer()
                                    Text(WorkTaskState(rawValue: task.status)?.label ?? "미상")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button("메모 보기") {
                                        taskNoteTaskId = task.id
                                        taskNoteDraft = ""
                                        taskNoteProposal = nil
                                        revisionSourceFilename = ""
                                        revisionSourceText = ""
                                        revisionDraft = ""
                                        revisionProposal = nil
                                        Task {
                                            await work.loadSavedNotes(
                                                projectId: selected.id, taskId: task.id)
                                        }
                                    }
                                    .disabled(work.busy || work.localFolder(projectId: selected.id) == nil)
                                    Menu("상태 변경") {
                                        ForEach(WorkTaskState.allCases) { state in
                                            Button(state.label) {
                                                Task {
                                                    await work.updateTask(projectId: selected.id,
                                                                          taskId: task.id,
                                                                          next: state)
                                                }
                                            }
                                            .disabled(work.busy || state.rawValue == task.status)
                                        }
                                    }
                                    .disabled(work.busy)
                                }
                                Divider()
                            }
                            Text("완료·막힘은 내가 기록하는 상태야. GitHub 조회나 AWS 배포 성공 여부와 자동으로 연결하지 않아.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Mac 코드 상태 · 사용자가 선택한 로컬 Git 저장소") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("연결된 프로젝트 폴더는 이 Mac의 앱 설정에만 저장합니다. 실제 코드는 확인 버튼을 눌렀을 때만 읽습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Button(work.localFolder(projectId: selected.id) == nil
                                       ? "Git 폴더 연결" : "다른 Git 폴더 선택") {
                                    chooseLocalFolder(projectId: selected.id)
                                }
                                .disabled(work.busy)
                                Button("현재 코드 상태 한 번 확인") {
                                    Task { await work.inspectLocalFolder(projectId: selected.id) }
                                }
                                .disabled(work.busy || work.localFolder(projectId: selected.id) == nil)
                                Button("연결 해제") {
                                    work.disconnectLocalFolder(projectId: selected.id)
                                }
                                .disabled(work.busy || work.localFolder(projectId: selected.id) == nil)
                            }
                            if let linked = work.localFolder(projectId: selected.id) {
                                Text("연결된 폴더: \(linked)")
                                    .font(.caption)
                                    .textSelection(.enabled)
                            } else {
                                Text("연결된 Mac 폴더 없음")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let evidence = work.localEvidence[selected.id] {
                                Text("로컬 브랜치: \(evidence.branch)")
                                Text("현재 로컬 HEAD: \(evidence.headSHA.prefix(12))")
                                    .textSelection(.enabled)
                                Text("Git 추적 변경 항목: \(evidence.changedTrackedEntries)개 · 미추적 항목: \(evidence.untrackedEntries)개")
                                Text("확인 시각: \(evidence.checkedAt.formatted(date: .abbreviated, time: .standard))")
                                    .font(.caption)
                                Text(evidence.isDirty
                                     ? "로컬 작업 폴더에 변경 항목이 있습니다. 자동 커밋하지 않았습니다."
                                     : "Git status 기준 변경 항목이 없습니다. 배포·원격 동기화 완료를 의미하지 않습니다.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let message = work.localMessages[selected.id] {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Text("GitHub 원격 기록과 Mac 로컬 코드는 서로 다를 수 있습니다. 파일 내용·파일명은 표시·업로드하지 않습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    WorkspaceResumePanel(
                        project: selected, work: work,
                        requestedWorkspace: taskWorkspaceRequest?.projectId == selected.id
                            ? taskWorkspaceRequest
                            : (requestedWorkspace?.projectId == selected.id
                                ? requestedWorkspace : nil)
                    )
                        .id(selected.id)
                    GroupBox("작업 실행 메모 · 미리보기 후 새 파일 1회 저장") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("실제로 연결한 Git 폴더 안의 .jarvis/notes에 Markdown 파일을 만듭니다. Git 커밋·푸시·코드 실행은 하지 않습니다. 민감한 정보를 입력하지 마세요.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if work.localFolder(projectId: selected.id) == nil {
                                Text("먼저 위에서 Git 폴더 연결을 직접 선택해 주세요.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let noteTask = selected.tasks.first(where: {
                                $0.id == taskNoteTaskId
                            }) {
                                Text("선택한 작업: \\(noteTask.title)")
                                    .font(.subheadline.weight(.medium))
                                Button("이 작업의 저장된 메모 목록 새로 읽기") {
                                    Task {
                                        await work.loadSavedNotes(
                                            projectId: selected.id, taskId: noteTask.id)
                                    }
                                }
                                .disabled(work.busy)
                                if work.savedNoteProjectId == selected.id &&
                                    work.savedNoteTaskId == noteTask.id {
                                    ForEach(work.savedNotes) { saved in
                                        HStack {
                                            Text(saved.filename)
                                                .font(.caption.monospaced())
                                                .textSelection(.enabled)
                                            Spacer()
                                            Button("내용 읽기") {
                                                revisionSourceFilename = ""
                                                revisionSourceText = ""
                                                revisionDraft = ""
                                                revisionProposal = nil
                                                Task {
                                                    await work.readSavedNote(
                                                        projectId: selected.id,
                                                        taskId: noteTask.id,
                                                        filename: saved.filename)
                                                }
                                            }
                                            .disabled(work.busy)
                                        }
                                    }
                                    if !work.savedNoteText.isEmpty {
                                        ScrollView {
                                            Text(work.savedNoteText)
                                                .font(.system(size: 12, design: .monospaced))
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(height: 220)
                                        Button("이 메모 수정본 작성") {
                                            revisionSourceFilename = work.savedNoteFilename
                                            revisionSourceText = work.savedNoteText
                                            revisionSourceProjectId = selected.id
                                            revisionSourceTaskId = noteTask.id
                                            revisionDraft = work.savedNoteText
                                            revisionProposal = nil
                                        }
                                        .disabled(work.busy || work.savedNoteFilename.isEmpty ||
                                                  (noteTask.status != "doing" && noteTask.status != "todo"))
                                    }
                                }
                                if revisionSourceProjectId == selected.id &&
                                    revisionSourceTaskId == noteTask.id &&
                                    !revisionSourceFilename.isEmpty {
                                    Text("원본 보존 · 수정본 새 파일 저장")
                                        .font(.subheadline.weight(.medium))
                                    Text("원본: \\(revisionSourceFilename)")
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                    TextEditor(text: $revisionDraft)
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(height: 200)
                                        .border(.gray.opacity(0.4))
                                        .onChange(of: revisionDraft) { _, _ in
                                            revisionProposal = nil
                                        }
                                    Button("수정본 전체 미리보기") {
                                        revisionProposal = JarvisNoteRevision.prepare(
                                            project: selected, task: noteTask,
                                            linkedFolder: work.localFolder(projectId: selected.id),
                                            originalFilename: revisionSourceFilename,
                                            originalText: revisionSourceText,
                                            revisedText: revisionDraft)
                                    }
                                    .disabled(work.busy ||
                                              revisionDraft == revisionSourceText ||
                                              revisionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                              revisionDraft.utf8.count > 16_000)
                                    if let revisionProposal {
                                        Text(revisionProposal.explanation)
                                            .font(.caption)
                                            .textSelection(.enabled)
                                        ScrollView {
                                            Text(revisionProposal.preview)
                                                .font(.system(size: 12, design: .monospaced))
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(height: 220)
                                        Button("새 수정본 저장 승인 화면") {
                                            revisionConfirmationVisible = true
                                        }
                                        .disabled(work.busy)
                                    }
                                }
                                if let receipt = work.revisionReceipt,
                                   receipt.projectId == selected.id,
                                   receipt.taskId == noteTask.id {
                                    Text(receipt.summary)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                                if !work.savedNoteMessage.isEmpty {
                                    Text(work.savedNoteMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if noteTask.status == "doing" || noteTask.status == "todo" {
                                    TextEditor(text: $taskNoteDraft)
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(height: 140)
                                        .border(.gray.opacity(0.4))
                                        .onChange(of: taskNoteDraft) { _, _ in
                                            taskNoteProposal = nil
                                        }
                                    Button("Markdown 저장 내용 미리보기") {
                                        taskNoteProposal = JarvisTaskNote.prepare(
                                            project: selected, task: noteTask,
                                            linkedFolder: work.localFolder(projectId: selected.id),
                                            steps: taskNoteDraft)
                                    }
                                    .disabled(work.busy ||
                                              work.localFolder(projectId: selected.id) == nil ||
                                              taskNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                              taskNoteDraft.count > 4000)
                                } else {
                                    Text("완료·막힘으로 기록된 작업은 이전 메모 읽기만 지원합니다.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("위의 ‘다음 할 일 시작’에서 원하는 작업의 실행 메모를 눌러 주세요.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let taskNoteProposal {
                                Text(taskNoteProposal.explanation)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                ScrollView {
                                    Text(taskNoteProposal.preview)
                                        .font(.system(size: 12, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 240)
                                Button("메모 파일 저장 승인 화면") {
                                    taskNoteConfirmationVisible = true
                                }
                                .disabled(work.busy)
                            }
                            if let receipt = work.taskNoteReceipt, receipt.projectId == selected.id {
                                Text(receipt.summary)
                                    .font(.caption)
                                    .textSelection(.enabled)
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
        .onChange(of: requestedWorkspace?.id) { _, _ in
            taskWorkspaceRequest = nil
            applyRequestedProject()
        }
        .confirmationDialog("이 작업의 상태를 진행 중으로 기록할까요?",
                            isPresented: $taskStartConfirmationVisible,
                            titleVisibility: .visible) {
            Button("승인하고 이 작업 시작 기록") {
                guard let proposal = taskStartProposal else { return }
                taskStartProposal = nil
                Task {
                    if await work.beginApprovedTask(proposal) {
                        taskWorkspaceRequest = JarvisWorkspaceCommand(
                            projectId: proposal.projectId,
                            projectName: proposal.projectName,
                            repository: proposal.repository, destination: .choose)
                    }
                }
            }
            Button("취소", role: .cancel) { taskStartProposal = nil }
        } message: {
            Text(taskStartProposal?.explanation ?? "승인할 작업이 없습니다.")
        }
        .confirmationDialog("원본은 보존하고 수정본 새 파일을 저장할까요?",
                            isPresented: $revisionConfirmationVisible,
                            titleVisibility: .visible) {
            Button("승인하고 수정본 새 파일 저장") {
                guard let proposal = revisionProposal else { return }
                revisionProposal = nil
                Task { _ = await work.saveApprovedRevision(proposal) }
            }
            Button("취소", role: .cancel) { revisionProposal = nil }
        } message: {
            Text(revisionProposal?.explanation ?? "승인할 수정본이 없습니다.")
        }
        .confirmationDialog("선택한 Markdown 파일을 새로 만들까요?",
                            isPresented: $taskNoteConfirmationVisible,
                            titleVisibility: .visible) {
            Button("승인하고 새 메모 파일 저장") {
                guard let proposal = taskNoteProposal else { return }
                taskNoteProposal = nil
                Task { _ = await work.saveApprovedTaskNote(proposal) }
            }
            Button("취소", role: .cancel) { taskNoteProposal = nil }
        } message: {
            Text(taskNoteProposal?.explanation ?? "승인할 메모가 없습니다.")
        }
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
