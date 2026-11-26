import Foundation
import Darwin

struct JarvisKnowledgeInventory: Decodable {
    struct Document: Decodable {
        let _id: String
        let title: String?
        let slug: String?
        let status: String?
        let humanVerified: Bool?
    }
    struct Category: Decodable { let title: String }
    let documents: [Document]
    let categories: [Category]

    func next(in catalog: JarvisKnowledgeCatalog) throws -> JarvisKnowledgeTopic? {
        let known = Set(catalog.topics.map(\.resolvedSlug))
        // Do not guess whether an unrecognized article is a duplicate.
        guard documents.allSatisfy({ $0.slug.map { known.contains($0) } ?? false }),
              let start = catalog.topics.firstIndex(where: { $0.code == catalog.continuationCode })
        else { throw CocoaError(.fileReadCorruptFile) }
        let occupied = Set(documents.compactMap(\.slug))
        guard let topic = catalog.topics[start...].first(where: { !occupied.contains($0.resolvedSlug) }) else { return nil }
        guard categories.filter({ $0.title == topic.category }).count == 1 else {
            throw CocoaError(.fileNoSuchFile)
        }
        return topic
    }
}

enum JarvisKnowledgeNightPolicy {
    static func deadline(at date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        guard calendar.component(.hour, from: date) == 0 else { return nil }
        return calendar.date(byAdding: .hour, value: 1, to: calendar.startOfDay(for: date))
    }
    static func mayStart(at now: Date, deadline: Date) -> Bool {
        // No new generation in the final five minutes.
        deadline.timeIntervalSince(now) >= 300
    }
    static func claim(root: URL, day: String) throws -> URL? {
        let folder = root.appendingPathComponent("night-shifts", isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(folder.appendingPathComponent("started.lock").path,
                             O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        if fd >= 0 { Darwin.close(fd); return folder }
        if errno == EEXIST { return nil }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
