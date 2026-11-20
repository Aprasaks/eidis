import Foundation

/// Only the user's local Git working copies are inspected, using read-only Git
/// commands. No GitHub token, push, fetch, checkout, or network request.
struct JarvisLocalGitRepository: Identifiable, Sendable {
    let path: String
    let name: String
    let branch: String
    let trackedChanged: Int?
    let latestCommit: String
    var id: String { path }
}

struct JarvisLocalGitSnapshot: Sendable {
    let repositories: [JarvisLocalGitRepository]
    let scannedLocations: [String]
    let checkedAt: Date
    let truncated: Bool
    let error: String?
}

enum JarvisLocalGitScanner {
    private static let maximumDirectories = 1200
    private static let maximumRepositories = 35
    private static let maximumDepth = 3

    /// Run only on a utility background task. File enumeration and git subprocesses
    /// must never block the SwiftUI main actor or its AVPlayer animation.
    nonisolated static func scan() -> JarvisLocalGitSnapshot {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = ["Documents", "Developer", "Projects", "Code"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { fm.fileExists(atPath: $0.path, isDirectory: nil) }
        var queue: [(URL, Int)] = roots.map { ($0, 0) }
        var repositoryPaths: [URL] = []
        var visited = 0
        var front = 0
        while front < queue.count && visited < maximumDirectories && repositoryPaths.count < maximumRepositories {
            let (directory, depth) = queue[front]
            front += 1
            visited += 1
            guard !Task<Never, Never>.isCancelled else { break }
            let git = directory.appendingPathComponent(".git")
            if fm.fileExists(atPath: git.path) {
                repositoryPaths.append(directory)
                continue // Never recursively list the internals of a Git worktree.
            }
            guard depth < maximumDepth else { continue }
            guard let children = try? fm.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
                options: []) else { continue }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if child.lastPathComponent.hasPrefix(".") { continue }
                guard let info = try? child.resourceValues(forKeys:
                    [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                    info.isDirectory == true, info.isSymbolicLink != true,
                    info.isPackage != true else { continue }
                queue.append((child, depth + 1))
            }
        }
        var entries: [JarvisLocalGitRepository] = []
        for repo in repositoryPaths.sorted(by: { $0.path < $1.path }) {
            guard !Task<Never, Never>.isCancelled else { break }
            let branch = runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repo) ?? "확인 불가"
            let status = runGit(["status", "--porcelain", "--untracked-files=no"], in: repo)
            let changes = status.map { $0.split(separator: "\n").count }
            let message = runGit(["log", "-1", "--format=%h %s"], in: repo) ?? "커밋 기록 확인 불가"
            entries.append(.init(path: repo.path, name: repo.lastPathComponent,
                                 branch: String(branch.prefix(80)), trackedChanged: changes,
                                 latestCommit: String(message.prefix(130))))
        }
        return JarvisLocalGitSnapshot(
            repositories: entries,
            scannedLocations: roots.map(\.lastPathComponent),
            checkedAt: Date(),
            truncated: visited >= maximumDirectories || repositoryPaths.count >= maximumRepositories,
            error: roots.isEmpty ? "검사 가능한 로컬 작업 폴더를 찾지 못했습니다." : nil)
    }

    private nonisolated static func runGit(_ args: [String], in directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false",
                             "-C", directory.path] + args
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0",
            "GIT_PAGER": "cat", "LC_ALL": "C"
        ]) { _, incoming in incoming }
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let bytes = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, bytes.count <= 32_000,
              let output = String(data: bytes, encoding: .utf8) else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
