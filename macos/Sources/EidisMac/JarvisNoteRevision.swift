import Foundation

/// An immutable proposal for a NEW version of a task note.
/// Editing never overwrites the original or changes the task status.
struct JarvisNoteRevisionProposal: Identifiable {
    let id = UUID()
    let projectId: Int
    let projectName: String
    let repository: String
    let taskId: Int
    let taskTitle: String
    let taskStatus: String
    let linkedFolder: String
    let originalFilename: String
    let originalText: String
    let revisedText: String
    let createdAt: Date
    let token: String

    var filename: String { "task-\(taskId)-\(token).md" }

    var preview: String {
        "<!-- JARVIS revision of \(originalFilename) -->\n\n" + revisedText
    }

    var explanation: String {
        "원본: .jarvis/notes/\(originalFilename)\n" +
        "새 수정본: .jarvis/notes/\(filename)\n" +
        "연결 폴더: \(linkedFolder)\n" +
        "원본 파일은 그대로 유지하고 새 버전만 추가합니다. " +
        "저장 직전 원본 내용이 달라졌으면 중단합니다. " +
        "커밋·배포·작업 완료 처리는 하지 않습니다."
    }
}

enum JarvisNoteRevisionError: LocalizedError {
    case invalidProposal
    case expired
    case targetChanged
    case originalChanged

    var errorDescription: String? {
        switch self {
        case .invalidProposal:
            "내용이 없거나 원본과 같거나 16KB를 초과하는 수정본입니다."
        case .expired:
            "수정 제안 승인 기한(2분)이 지났습니다."
        case .targetChanged:
            "프로젝트·작업·연결 경로가 수정 제안 당시와 다릅니다."
        case .originalChanged:
            "원본 메모가 다른 곳에서 변경됐습니다. 덮어쓰지 않았습니다. 다시 읽어 주세요."
        }
    }
}

enum JarvisNoteRevision {
    static func prepare(
        project: WorkProject, task: WorkTask,
        linkedFolder: String?, originalFilename: String,
        originalText: String, revisedText: String,
        at date: Date = Date(),
        token: String = String(UUID().uuidString.prefix(8))
    ) -> JarvisNoteRevisionProposal? {
        guard let linkedFolder,
              task.id > 0,
              (task.status == "doing" || task.status == "todo"),
              project.tasks.contains(where: {
                  $0.id == task.id && $0.title == task.title &&
                  $0.status == task.status
              }),
              token.range(of: #"^[0-9A-F]{8}$"#,
                          options: .regularExpression) != nil,
              originalFilename.range(
                  of: "^task-\(task.id)-[A-F0-9]{8}\\.md$",
                  options: .regularExpression) != nil,
              !originalText.isEmpty,
              !revisedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              revisedText != originalText,
              revisedText.utf8.count <= 16_000 else { return nil }
        let proposed = JarvisNoteRevisionProposal(
            projectId: project.id, projectName: project.name,
            repository: project.repoFullName, taskId: task.id,
            taskTitle: task.title, taskStatus: task.status,
            linkedFolder: linkedFolder, originalFilename: originalFilename,
            originalText: originalText, revisedText: revisedText,
            createdAt: date, token: token)
        guard proposed.preview.utf8.count <= 16_384 else { return nil }
        return proposed
    }

    /// Save a separate revised version only if the original file *still*
    /// matches what the user read. The existing immutable guarded writer
    /// enforces O_EXCL, no symlinks, fixed path, fsync and read-back equality.
    static func save(
        _ proposal: JarvisNoteRevisionProposal,
        currentProject: WorkProject?, currentLinkedFolder: String?,
        at date: Date = Date()
    ) throws -> JarvisTaskNoteReceipt {
        let age = date.timeIntervalSince(proposal.createdAt)
        guard (0...120).contains(age) else {
            throw JarvisNoteRevisionError.expired
        }
        guard let project = currentProject,
              project.id == proposal.projectId,
              project.name == proposal.projectName,
              project.repoFullName == proposal.repository,
              currentLinkedFolder == proposal.linkedFolder,
              let task = project.tasks.first(where: {
                  $0.id == proposal.taskId &&
                  $0.title == proposal.taskTitle &&
                  $0.status == proposal.taskStatus
              }) else {
            throw JarvisNoteRevisionError.targetChanged
        }
        guard let verified = prepare(
            project: project, task: task,
            linkedFolder: currentLinkedFolder,
            originalFilename: proposal.originalFilename,
            originalText: proposal.originalText,
            revisedText: proposal.revisedText,
            at: proposal.createdAt, token: proposal.token),
              verified.preview == proposal.preview else {
            throw JarvisNoteRevisionError.invalidProposal
        }

        // The read-only note reader enforces the same task ID, regular-file
        // check, 16KB ceiling and O_NOFOLLOW as the list UI.
        let current = try JarvisNoteLibrary.read(
            filename: proposal.originalFilename,
            taskId: proposal.taskId,
            linkedFolder: proposal.linkedFolder)
        guard current == proposal.originalText else {
            throw JarvisNoteRevisionError.originalChanged
        }
        guard let revision = JarvisTaskNote.prepareRevision(
            project: project, task: task,
            linkedFolder: proposal.linkedFolder,
            markdown: proposal.preview, at: proposal.createdAt,
            token: proposal.token) else {
            throw JarvisNoteRevisionError.invalidProposal
        }
        return try JarvisTaskNote.save(
            revision, currentProject: project,
            currentLinkedFolder: currentLinkedFolder, at: date)
    }
}
