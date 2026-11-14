import Foundation

/// Routes only an explicit project-open request originating in the native
/// Speech tab. Parsing is deterministic and never executes or opens anything.
struct JarvisWorkspaceCommand: Identifiable {
    enum Destination {
        case choose, github, folder
    }

    let id = UUID()
    let projectId: Int
    let projectName: String
    let repository: String
    let destination: Destination
}

enum JarvisWorkspaceCommandParser {
    enum Result {
        case ordinary
        case matched(JarvisWorkspaceCommand)
        case missingProject
        case ambiguous
        case unsupported
    }

    static func isOpenRequest(_ text: String) -> Bool {
        let compact = normalize(text)
        let hasOpenVerb = ["열어", "열기", "열어줘", "열고", "열어서", "open"].contains {
            compact.contains($0)
        }
        let projectScope = ["프로젝트", "작업", "이어서", "이어", "github",
                            "깃허브", "깃헙", "finder", "폴더", "repository",
                            "저장소"].contains { compact.contains($0) }
        return hasOpenVerb && projectScope
    }

    static func parse(_ text: String, projects: [WorkProject]) -> Result {
        guard isOpenRequest(text) else { return .ordinary }
        let compact = normalize(text)
        guard !["삭제", "지워", "푸시", "push", "커밋", "commit",
                 "배포", "deploy", "결제", "전송", "발행"].contains(where: {
                     compact.contains($0)
                 }) else { return .unsupported }

        let matched = projects.filter {
            let name = normalize($0.name)
            return !name.isEmpty && compact.contains(name)
        }
        guard !matched.isEmpty else { return .missingProject }
        guard matched.count == 1, let project = matched.first else { return .ambiguous }

        let destination: JarvisWorkspaceCommand.Destination
        let github = ["github", "깃허브", "깃헙"].contains { compact.contains($0) }
        let folder = ["finder", "폴더"].contains { compact.contains($0) }
        if github && !folder { destination = .github }
        else if folder && !github { destination = .folder }
        else { destination = .choose }

        return .matched(JarvisWorkspaceCommand(
            projectId: project.id, projectName: project.name,
            repository: project.repoFullName, destination: destination))
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && !$0.isNewline }
    }
}
