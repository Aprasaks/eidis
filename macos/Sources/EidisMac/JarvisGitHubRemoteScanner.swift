import Foundation

/// Read-only GitHub account snapshot using the Mac's existing gh authentication.
/// No token is loaded into JARVIS, emitted to logs, or stored in SQLite.
struct JarvisGitHubRemoteRepository: Decodable, Identifiable, Sendable {
    let fullName: String
    let privateRepo: Bool
    let pushedAt: String?
    let defaultBranch: String?
    let openIssueOrPrCount: Int?
    var id: String { fullName }
}

struct JarvisGitHubRemoteSnapshot: Sendable {
    let repositories: [JarvisGitHubRemoteRepository]
    let checkedAt: Date
    let truncated: Bool
    let error: String?
}

enum JarvisGitHubRemoteScanner {
    private static let maximumDisplayed = 100

    /// Execute only on a background task. CLI command is fixed: GET-only.
    /// Does not call git push, auth token, API writes, or any user-supplied command.
    nonisolated static func scan() -> JarvisGitHubRemoteSnapshot {
        let fm = FileManager.default
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        guard let executable = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            return failure("GitHub CLI가 설치되어 있지 않습니다.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "api", "--method", "GET", "--paginate",
            "/user/repos?per_page=100&affiliation=owner,collaborator,organization_member&sort=updated&direction=desc",
            "--jq",
            ".[] | {fullName: .full_name, privateRepo: .private, pushedAt: .pushed_at, defaultBranch: .default_branch, openIssueOrPrCount: .open_issues_count}"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_HTTP_TIMEOUT"] = "10"
        environment["NO_COLOR"] = "1"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        // Never show CLI errors: they may include account or authentication details.
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { return failure("GitHub CLI 실행에 실패했습니다.") }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return failure("GitHub 인증 또는 네트워크 연결을 확인해 주세요.")
        }
        guard data.count <= 1_000_000, let text = String(data: data, encoding: .utf8) else {
            return failure("GitHub 응답이 표시 가능한 크기를 초과했습니다.")
        }
        let decoder = JSONDecoder()
        var repositories: [JarvisGitHubRemoteRepository] = []
        for line in text.split(separator: "\n") {
            guard let bytes = String(line).data(using: .utf8),
                  let item = try? decoder.decode(JarvisGitHubRemoteRepository.self, from: bytes) else {
                return failure("GitHub 응답 형식이 예상과 다릅니다.")
            }
            repositories.append(item)
        }
        let ordered = repositories.sorted {
            ($0.pushedAt ?? "") > ($1.pushedAt ?? "")
        }
        return JarvisGitHubRemoteSnapshot(
            repositories: Array(ordered.prefix(maximumDisplayed)),
            checkedAt: Date(),
            truncated: ordered.count > maximumDisplayed,
            error: nil)
    }

    private static func failure(_ message: String) -> JarvisGitHubRemoteSnapshot {
        JarvisGitHubRemoteSnapshot(repositories: [], checkedAt: Date(),
                                   truncated: false, error: message)
    }
}
