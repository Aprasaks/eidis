import Darwin
import Foundation

/// Explicitly scoped, one-time proposal to create a Markdown execution note.
/// The proposal and preview are read-only. File creation is a separate user
/// action and never commits, pushes or executes the user's task.
struct JarvisTaskNoteProposal: Identifiable {
    let id = UUID()
    let projectId: Int
    let projectName: String
    let repository: String
    let taskId: Int
    let taskTitle: String
    let taskStatus: String
    let linkedFolder: String
    let createdAt: Date
    let token: String
    let steps: String

    var filename: String { "task-\(taskId)-\(token).md" }
    var relativePath: String { ".jarvis/notes/\(filename)" }

    var preview: String {
        """
        # 작업 실행 메모

        프로젝트: \(projectName)
        저장소: \(repository.isEmpty ? "등록되지 않음" : repository)
        작업 번호: \(taskId)
        작업: \(taskTitle)
        기록 당시 상태: \(taskStatus == "doing" ? "진행" : "예정")

        ## 직접 확인하고 실행할 단계

        \(steps)

        ## 실행 결과 및 검증

        - [ ] 실제 작업 수행 여부 확인
        - [ ] 변경 사항 및 근거 기록
        - [ ] 완료 조건 직접 검증

        > 이 문서는 실행 계획과 기록을 위한 초안입니다.
        > 작업 완료·코드 수정·배포 성공을 증명하지 않습니다.
        """
    }

    var explanation: String {
        "선택한 Mac 폴더: \(linkedFolder)\n파일: \(relativePath)\n" +
        "이 파일을 새로 생성합니다. 기존 파일 덮어쓰기·코드 수정·Git 커밋·푸시·배포는 하지 않습니다. " +
        "파일은 Git 폴더 안에 생성되므로 이후 사용자가 직접 커밋할 경우 포함될 수 있습니다."
    }
}

struct JarvisTaskNoteReceipt {
    let projectId: Int
    let taskId: Int
    let savedPath: String
    let savedBytes: Int

    var summary: String {
        "실행 메모 생성·내용 검증 완료: \(savedPath) (\(savedBytes)바이트). " +
        "작업 상태·코드·Git 원격은 변경하지 않았습니다."
    }
}

enum JarvisTaskNoteError: LocalizedError {
    case invalidProposal
    case expired
    case targetChanged
    case invalidFolder
    case cannotCreate
    case alreadyExists
    case cannotVerify

    var errorDescription: String? {
        switch self {
        case .invalidProposal: "유효한 작업 메모 제안이 아닙니다."
        case .expired: "2분이 지났습니다. 메모 제안을 다시 만드세요."
        case .targetChanged: "프로젝트·작업 내용 또는 연결된 폴더가 바뀌었습니다."
        case .invalidFolder: "연결된 Git 폴더가 없거나 경로가 안전하지 않습니다."
        case .cannotCreate: "새 메모 파일을 생성하지 못했습니다."
        case .alreadyExists: "같은 이름의 메모가 이미 있습니다. 덮어쓰지 않았습니다."
        case .cannotVerify: "저장된 파일 내용을 확인하지 못했습니다. 파일 상태를 수동 확인해 주세요."
        }
    }
}

enum JarvisTaskNote {
    static func initialSteps() -> String {
        """
        1. 이 작업의 현재 상태와 완료 조건을 확인한다.
        2. 필요한 자료와 연결된 프로젝트의 변경 사항을 검토한다.
        3. 수행할 구체적인 작업과 결과를 이곳에 기록한다.
        4. 실제 결과를 확인한 후에만 작업 완료로 표시한다.
        """
    }

    static func prepare(project: WorkProject, task: WorkTask,
                        linkedFolder: String?, steps: String,
                        at date: Date = Date(),
                        token: String = String(UUID().uuidString.prefix(8))) -> JarvisTaskNoteProposal? {
        guard task.id > 0, (task.status == "doing" || task.status == "todo"),
              project.tasks.contains(where: {
                  $0.id == task.id && $0.title == task.title && $0.status == task.status
              }),
              let linkedFolder, linkedFolder.hasPrefix("/"), linkedFolder.count <= 4096,
              token.range(of: #"^[0-9A-F]{8}$"#,
                          options: .regularExpression) != nil else { return nil }
        let cleanSteps = steps.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...4000).contains(cleanSteps.count) else { return nil }
        return JarvisTaskNoteProposal(
            projectId: project.id, projectName: project.name,
            repository: project.repoFullName, taskId: task.id,
            taskTitle: task.title, taskStatus: task.status,
            linkedFolder: linkedFolder, createdAt: date,
            token: token, steps: cleanSteps)
    }

    /// All child paths have fixed names; the only generated filename contains
    /// a numeric task ID and an 8-character uppercase hex token. O_NOFOLLOW
    /// rejects redirected directories; O_EXCL protects existing files.
    static func save(_ proposal: JarvisTaskNoteProposal,
                     currentProject: WorkProject?,
                     currentLinkedFolder: String?,
                     at date: Date = Date()) throws -> JarvisTaskNoteReceipt {
        let age = date.timeIntervalSince(proposal.createdAt)
        guard (0...120).contains(age) else { throw JarvisTaskNoteError.expired }
        guard let project = currentProject,
              project.id == proposal.projectId,
              project.name == proposal.projectName,
              project.repoFullName == proposal.repository,
              currentLinkedFolder == proposal.linkedFolder,
              project.tasks.contains(where: {
                  $0.id == proposal.taskId &&
                  $0.title == proposal.taskTitle &&
                  $0.status == proposal.taskStatus
              }) else { throw JarvisTaskNoteError.targetChanged }
        guard proposal.taskId > 0,
              proposal.token.range(of: #"^[0-9A-F]{8}$"#,
                                    options: .regularExpression) != nil,
              (1...4000).contains(proposal.steps.count) else {
            throw JarvisTaskNoteError.invalidProposal
        }
        let folder = URL(fileURLWithPath: proposal.linkedFolder, isDirectory: true)
        let canonical = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical.path == proposal.linkedFolder else {
            throw JarvisTaskNoteError.invalidFolder
        }

        let root = Darwin.open(canonical.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw JarvisTaskNoteError.invalidFolder }
        defer { _ = Darwin.close(root) }
        var gitInfo = stat()
        guard fstatat(root, ".git", &gitInfo, AT_SYMLINK_NOFOLLOW) == 0,
              (gitInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) ||
              (gitInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw JarvisTaskNoteError.invalidFolder
        }

        func safeSubdirectory(_ name: String, parent: Int32) throws -> Int32 {
            if mkdirat(parent, name, mode_t(S_IRWXU)) != 0 && errno != EEXIST {
                throw JarvisTaskNoteError.cannotCreate
            }
            let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw JarvisTaskNoteError.invalidFolder }
            return fd
        }
        let hidden = try safeSubdirectory(".jarvis", parent: root)
        defer { _ = Darwin.close(hidden) }
        let notes = try safeSubdirectory("notes", parent: hidden)
        defer { _ = Darwin.close(notes) }

        let file = openat(notes, proposal.filename,
                          O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                          mode_t(S_IRUSR | S_IWUSR))
        if file < 0 {
            if errno == EEXIST { throw JarvisTaskNoteError.alreadyExists }
            throw JarvisTaskNoteError.cannotCreate
        }
        let bytes = Array(proposal.preview.utf8)
        var offset = 0
        var valid = false
        defer {
            _ = Darwin.close(file)
            if !valid { _ = unlinkat(notes, proposal.filename, 0) }
        }
        while offset < bytes.count {
            let count = bytes.withUnsafeBytes { raw -> Int in
                Darwin.write(file, raw.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            guard count > 0 else { throw JarvisTaskNoteError.cannotCreate }
            offset += count
        }
        guard fsync(file) == 0 else { throw JarvisTaskNoteError.cannotVerify }

        // Verify bytes against the exact immutable approved preview. The
        // returned path is never opened in Finder without another approval.
        let verification = openat(notes, proposal.filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard verification >= 0 else { throw JarvisTaskNoteError.cannotVerify }
        defer { _ = Darwin.close(verification) }
        var actual = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let capacity = buffer.count
        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                Darwin.read(verification, raw.baseAddress, capacity)
            }
            guard count >= 0 else { throw JarvisTaskNoteError.cannotVerify }
            if count == 0 { break }
            guard actual.count + count <= 16_384 else {
                throw JarvisTaskNoteError.cannotVerify
            }
            actual.append(contentsOf: buffer.prefix(count))
        }
        guard actual == bytes else { throw JarvisTaskNoteError.cannotVerify }
        valid = true
        return JarvisTaskNoteReceipt(
            projectId: proposal.projectId, taskId: proposal.taskId,
            savedPath: canonical.appendingPathComponent(proposal.relativePath).path,
            savedBytes: bytes.count)
    }
}
