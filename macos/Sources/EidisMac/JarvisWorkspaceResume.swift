import AppKit
import Foundation

/// An immutable, scoped proposal. Creating or displaying it never opens apps,
/// reads project files, calls GitHub or modifies the user's work.
struct JarvisWorkspaceProposal {
    let projectId: Int
    let projectName: String
    let repository: String
    let localFolder: String?
    let githubURL: URL?
    let createdAt: Date

    var description: String {
        var items: [String] = []
        if let localFolder {
            items.append("Finder에서 폴더 열기: \(localFolder)")
        }
        if let githubURL {
            items.append("브라우저에서 GitHub 열기: \(githubURL.absoluteString)")
        }
        return items.joined(separator: "\n")
            + "\n이동만 요청합니다. 파일을 수정하거나 커밋·푸시·배포하지 않습니다. GitHub는 브라우저에서 네트워크 요청이 발생할 수 있습니다."
    }
}

struct JarvisWorkspaceReceipt {
    let projectId: Int
    let timestamp: Date
    let details: [String]

    var summary: String {
        "선택한 프로젝트의 앱 열기 요청 결과 (\(ISO8601DateFormatter().string(from: timestamp)))\n"
            + details.joined(separator: "\n")
            + "\n'열기 요청 수락'은 실제 페이지 로딩이나 폴더 내용 확인을 뜻하지 않습니다."
    }
}

enum JarvisWorkspaceResume {
    /// Reject arbitrary URL strings and non-GitHub hosts; do not allow
    /// query/fragment characters, scheme changes or slash-injection.
    static func githubURL(for repository: String) -> URL? {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({
                  (1...100).contains($0.count)
                      && $0.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
                                  options: .regularExpression) != nil
                      && !$0.contains("..")
              }) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repository)"
        guard let url = components.url,
              url.scheme == "https", url.host == "github.com",
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    static func prepare(project: WorkProject, linkedFolder: String?,
                        openFolder: Bool, openGitHub: Bool,
                        now: Date = Date()) -> JarvisWorkspaceProposal? {
        guard openFolder || openGitHub else { return nil }
        let folder: String?
        if openFolder {
            guard let linkedFolder, linkedFolder.hasPrefix("/"),
                  linkedFolder.count <= 4096 else { return nil }
            folder = linkedFolder
        } else {
            folder = nil
        }
        let url: URL?
        if openGitHub {
            guard let parsed = githubURL(for: project.repoFullName) else { return nil }
            url = parsed
        } else {
            url = nil
        }
        return JarvisWorkspaceProposal(
            projectId: project.id, projectName: project.name,
            repository: project.repoFullName, localFolder: folder,
            githubURL: url, createdAt: now)
    }

    /// This call is ONLY wired to the explicit "승인하고..." confirmation button.
    /// The supplied opener can be mocked to test every guard without opening
    /// Finder or the user's browser.
    static func perform(
        proposal: JarvisWorkspaceProposal, currentProject: WorkProject?,
        currentLinkedFolder: String?, now: Date = Date(),
        opener: (URL) -> Bool
    ) -> JarvisWorkspaceReceipt {
        func receipt(_ messages: [String]) -> JarvisWorkspaceReceipt {
            JarvisWorkspaceReceipt(projectId: proposal.projectId,
                                   timestamp: now, details: messages)
        }
        guard let project = currentProject,
              project.id == proposal.projectId,
              project.name == proposal.projectName,
              project.repoFullName == proposal.repository else {
            return receipt(["실행 차단: 승인 이후 프로젝트 정보가 바뀌었습니다. 다시 제안하세요."])
        }
        let age = now.timeIntervalSince(proposal.createdAt)
        guard (0...120).contains(age) else {
            return receipt(["실행 차단: 승인 제안이 2분을 넘었거나 시각이 올바르지 않습니다."])
        }
        guard proposal.localFolder != nil || proposal.githubURL != nil else {
            return receipt(["실행 차단: 승인한 대상이 없습니다."])
        }
        if let folder = proposal.localFolder {
            guard currentLinkedFolder == folder else {
                return receipt(["실행 차단: 연결된 Mac 폴더가 변경됐습니다. 다시 제안하세요."])
            }
        }
        if let url = proposal.githubURL {
            guard url == githubURL(for: project.repoFullName) else {
                return receipt(["실행 차단: GitHub 주소가 승인 대상과 다릅니다."])
            }
        }

        var results: [String] = []
        if let path = proposal.localFolder {
            let raw = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            let canonical = raw.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            // A symlink changed since the user linked the folder, or it is
            // no longer a Git root: do not open a substituted directory.
            if canonical.path != path
                || !FileManager.default.fileExists(atPath: canonical.path,
                                                   isDirectory: &isDirectory)
                || !isDirectory.boolValue
                || !FileManager.default.fileExists(atPath:
                                                   canonical.appendingPathComponent(".git").path) {
                results.append("Finder: 대상 폴더가 이동·변경되었거나 Git 루트가 아닙니다. 열지 않았습니다.")
            } else {
                let accepted = opener(canonical)
                results.append(accepted
                    ? "Finder: 선택한 로컬 프로젝트 폴더 열기 요청 수락"
                    : "Finder: 폴더 열기 요청 실패")
            }
        }
        if let url = proposal.githubURL {
            let accepted = opener(url)
            results.append(accepted
                ? "브라우저: \(proposal.repository) GitHub 페이지 열기 요청 수락"
                : "브라우저: \(proposal.repository) GitHub 페이지 열기 요청 실패")
        }
        return receipt(results)
    }
}
