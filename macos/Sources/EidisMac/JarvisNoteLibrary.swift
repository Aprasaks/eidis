import Darwin
import Foundation

/// Read-only access to notes written by JARVIS under a user-linked Git root.
/// No shell, network, arbitrary path argument, directory creation or write.
struct JarvisSavedNote: Identifiable {
    let filename: String
    let modifiedAt: Date
    let bytes: Int

    var id: String { filename }
}

enum JarvisNoteLibraryError: LocalizedError {
    case invalidFolder
    case invalidName
    case unreadable
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFolder:
            "연결한 Git 폴더 또는 메모 경로가 안전하지 않습니다."
        case .invalidName:
            "선택한 작업의 자비스 메모 이름이 아닙니다."
        case .unreadable:
            "메모를 읽을 수 없습니다. 파일이 변경되었을 수 있습니다."
        case .tooLarge:
            "메모가 16KB 제한을 초과해 읽기를 중단했습니다."
        }
    }
}

enum JarvisNoteLibrary {
    private static let maxBytes = 16_384

    private static func isAllowed(_ filename: String, taskId: Int) -> Bool {
        guard taskId > 0 else { return false }
        return filename.range(
            of: "^task-\(taskId)-[A-F0-9]{8}\\.md$",
            options: .regularExpression) != nil
    }

    // For a valid empty Git repo, there may be no .jarvis/notes yet. This
    // returns nil for absent directories. Existing redirected directories
    // or invalid Git roots are rejected instead of followed.
    private static func withNotes<T>(
        folder linkedFolder: String, _ block: (Int32) throws -> T
    ) throws -> T? {
        guard linkedFolder.hasPrefix("/"), linkedFolder.count <= 4096 else {
            throw JarvisNoteLibraryError.invalidFolder
        }
        let canonical = URL(fileURLWithPath: linkedFolder, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard canonical.path == linkedFolder else {
            throw JarvisNoteLibraryError.invalidFolder
        }
        let root = Darwin.open(
            canonical.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw JarvisNoteLibraryError.invalidFolder }
        defer { _ = Darwin.close(root) }

        var gitInfo = stat()
        guard fstatat(root, ".git", &gitInfo, AT_SYMLINK_NOFOLLOW) == 0,
              (gitInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) ||
              (gitInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw JarvisNoteLibraryError.invalidFolder
        }
        let hidden = openat(
            root, ".jarvis", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if hidden < 0 {
            if errno == ENOENT { return nil }
            throw JarvisNoteLibraryError.invalidFolder
        }
        defer { _ = Darwin.close(hidden) }
        let notes = openat(
            hidden, "notes", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if notes < 0 {
            if errno == ENOENT { return nil }
            throw JarvisNoteLibraryError.invalidFolder
        }
        defer { _ = Darwin.close(notes) }
        return try block(notes)
    }

    static func list(taskId: Int, linkedFolder: String) throws -> [JarvisSavedNote] {
        guard taskId > 0 else { throw JarvisNoteLibraryError.invalidName }
        return try withNotes(folder: linkedFolder) { notes in
            let duplicated = dup(notes)
            guard duplicated >= 0 else { throw JarvisNoteLibraryError.unreadable }
            guard let stream = fdopendir(duplicated) else {
                _ = Darwin.close(duplicated)
                throw JarvisNoteLibraryError.unreadable
            }
            defer { _ = closedir(stream) }
            var found: [JarvisSavedNote] = []
            var count = 0
            while let entry = readdir(stream) {
                count += 1
                guard count <= 5000 else { throw JarvisNoteLibraryError.unreadable }
                let filename = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: 1024) {
                        String(cString: $0)
                    }
                }
                guard isAllowed(filename, taskId: taskId) else { continue }
                var information = stat()
                guard fstatat(notes, filename, &information, AT_SYMLINK_NOFOLLOW) == 0,
                      (information.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
                      information.st_size >= 0,
                      information.st_size <= maxBytes else { continue }
                found.append(JarvisSavedNote(
                    filename: filename,
                    modifiedAt: Date(
                        timeIntervalSince1970:
                            Double(information.st_mtimespec.tv_sec) +
                            Double(information.st_mtimespec.tv_nsec) / 1_000_000_000),
                    bytes: Int(information.st_size)))
            }
            return Array(found.sorted {
                if $0.modifiedAt != $1.modifiedAt {
                    return $0.modifiedAt > $1.modifiedAt
                }
                return $0.filename > $1.filename
            }.prefix(20))
        } ?? []
    }

    static func read(
        filename: String, taskId: Int, linkedFolder: String
    ) throws -> String {
        guard isAllowed(filename, taskId: taskId) else {
            throw JarvisNoteLibraryError.invalidName
        }
        guard let result = try withNotes(folder: linkedFolder, { notes in
            let file = openat(
                notes, filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard file >= 0 else { throw JarvisNoteLibraryError.unreadable }
            defer { _ = Darwin.close(file) }
            var info = stat()
            guard fstat(file, &info) == 0,
                  (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                throw JarvisNoteLibraryError.unreadable
            }
            guard info.st_size >= 0, info.st_size <= maxBytes else {
                throw JarvisNoteLibraryError.tooLarge
            }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            let capacity = buffer.count
            while true {
                let readCount = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.read(file, bytes.baseAddress, capacity)
                }
                guard readCount >= 0 else { throw JarvisNoteLibraryError.unreadable }
                if readCount == 0 { break }
                guard data.count + readCount <= maxBytes else {
                    throw JarvisNoteLibraryError.tooLarge
                }
                data.append(contentsOf: buffer.prefix(readCount))
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw JarvisNoteLibraryError.unreadable
            }
            return text
        }) else {
            throw JarvisNoteLibraryError.unreadable
        }
        return result
    }
}
