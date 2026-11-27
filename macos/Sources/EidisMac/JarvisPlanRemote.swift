import Foundation

/// 아이폰 이디스 "기억" 탭의 프로젝트 기획서 (읽기 전용).
///
/// 연결·암호화·기기 인증은 JarvisMacNearbyCalendar가 맡고, 이 파일은 인증된 요청에
/// 무엇을 돌려줄지만 정한다.
/// 보내는 것: 저장소 docs/ 폴더의 기획서(*_PLAN_*.md) 제목·수정 시각·본문.
/// 보내지 않는 것: 그 밖의 파일, 비밀값, 작업 로그.
@MainActor
enum JarvisPlanRemote {
    static let requestKind = "planDocsRequest"
    /// 메시지 하나가 500KB를 넘으면 버려지므로 본문 합계를 이보다 작게 담는다.
    private static let totalBudget = 300_000
    private static let perDocLimit = 120_000

    static var docsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/JARVIS-FULLSCREEN-PREVIEW/docs", isDirectory: true)
    }

    /// kind "planDocsRequest" → "planDocs"
    static func docs(requestID: String) -> [String: Any] {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: docsFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "md" && $0.lastPathComponent.contains("_PLAN_") }
            .map { url -> (URL, Date) in
                (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
        var budget = totalBudget
        var docs: [[String: Any]] = []
        for (url, modified) in files {
            guard budget > 0, let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let body = String(text.prefix(min(perDocLimit, budget)))
            budget -= body.utf8.count
            let title = text.split(separator: "\n").first { $0.hasPrefix("# ") }
                .map { String($0.dropFirst(2)) } ?? url.deletingPathExtension().lastPathComponent
            docs.append([
                "file": url.lastPathComponent, "title": title,
                "updatedAt": ISO8601DateFormatter().string(from: modified),
                "markdown": body, "truncated": body.count < text.count
            ])
        }
        return ["kind": "planDocs", "requestID": requestID,
                "checkedAt": ISO8601DateFormatter().string(from: Date()), "docs": docs]
    }
}
