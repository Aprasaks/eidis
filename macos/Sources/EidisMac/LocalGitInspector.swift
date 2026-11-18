import Foundation

/// A one-shot local Git snapshot. No network, no Git writes, and no file contents.
/// A folder must be chosen explicitly in the native UI before this is invoked.
struct LocalGitEvidence {
    let rootPath: String
    let branch: String
    let headSHA: String
    let changedTrackedEntries: Int
    let untrackedEntries: Int
    let checkedAt: Date

    var isDirty: Bool { changedTrackedEntries + untrackedEntries > 0 }
}

enum LocalGitError: LocalizedError {
    case invalidFolder, invalidRepository, invalidOutput, tooMuchOutput, gitFailed

    var errorDescription: String? {
        switch self {
        case .invalidFolder: "선택한 폴더에 접근할 수 없습니다."
        case .invalidRepository: "선택한 폴더는 확인 가능한 Git 작업 저장소가 아닙니다."
        case .invalidOutput: "Git 응답을 신뢰할 수 없습니다."
        case .tooMuchOutput: "변경 항목이 너무 많아 안전하게 중단했습니다."
        case .gitFailed: "Git 읽기 작업에 실패하거나 시간이 초과됐습니다."
        }
    }
}

enum LocalGitInspector {
    private static let outputLimit = 524_288
    private static let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

    static func inspect(folderURL: URL) throws -> LocalGitEvidence {
        guard folderURL.isFileURL else { throw LocalGitError.invalidFolder }
        let folder = folderURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir),
              isDir.boolValue else { throw LocalGitError.invalidFolder }

        let rootData = try invoke(["rev-parse", "--show-toplevel"], folder: folder)
        guard let path = String(data: rootData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              path.hasPrefix("/") else { throw LocalGitError.invalidRepository }
        let root = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw LocalGitError.invalidRepository
        }

        let branch = try stringResult(
            invoke(["rev-parse", "--abbrev-ref", "HEAD"], folder: root))
        let head = try stringResult(
            invoke(["rev-parse", "--verify", "HEAD"], folder: root))
        guard (head.count == 40 || head.count == 64),
              head.unicodeScalars.allSatisfy({ hex.contains($0) }),
              !branch.isEmpty, branch.count <= 200 else {
            throw LocalGitError.invalidOutput
        }
        // -z separates entries by NUL, so arbitrary filenames cannot be mistaken
        // for multiple changes. --no-renames keeps a single entry per change.
        // This does NOT read file contents or list filenames in the UI.
        let status = try invoke(
            ["status", "--porcelain=v1", "-z", "--untracked-files=normal",
             "--no-renames"], folder: root)
        let counts = try countStatus(status)
        return LocalGitEvidence(
            rootPath: root.path, branch: branch, headSHA: head,
            changedTrackedEntries: counts.tracked, untrackedEntries: counts.untracked,
            checkedAt: Date())
    }

    static func countStatus(_ raw: Data) throws -> (tracked: Int, untracked: Int) {
        var tracked = 0
        var untracked = 0
        for item in raw.split(separator: 0) {
            guard item.count >= 4, item[item.startIndex + 2] == 32 else {
                throw LocalGitError.invalidOutput
            }
            let a = item[item.startIndex]
            let b = item[item.startIndex + 1]
            if a == 63 && b == 63 { untracked += 1 }
            else { tracked += 1 }
        }
        return (tracked, untracked)
    }

    private static func stringResult(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw LocalGitError.invalidOutput
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func invoke(_ command: [String], folder: URL) throws -> Data {
        let process = Process()
        // Fixed executable and fixed Git subcommands; no shell or caller-supplied
        // command arguments. --no-optional-locks prevents optional index updates,
        // and fsmonitor=false prevents invoking configured filesystem monitors.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "--no-optional-locks", "-c", "core.fsmonitor=false",
            "-C", folder.path
        ] + command
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw LocalGitError.gitFailed }

        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: timeout)
        var data = Data()
        while let chunk = try? pipe.fileHandleForReading.read(upToCount: 8192),
              !chunk.isEmpty {
            guard data.count + chunk.count <= outputLimit else {
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                timeout.cancel()
                throw LocalGitError.tooMuchOutput
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else {
            throw LocalGitError.gitFailed
        }
        return data
    }
}
