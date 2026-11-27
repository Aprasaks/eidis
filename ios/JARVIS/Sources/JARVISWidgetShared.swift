import Foundation

/// 앱과 위젯이 함께 쓰는 요약 (App Group 공유 저장소).
/// 앱이 Mac에서 실제로 받은 값만 쓴다. 위젯은 읽기만 하며, 값이 없으면 "—"로 보여준다.
struct JARVISWidgetSummary: Codable {
    var igFollowers: Int?
    var threadsFollowers: Int?
    var facebookFollowers: Int?
    var youtubeSubscribers: Int?
    var waitingApprovals: Int
    var nextPostTitle: String?      // 승인돼 22시 게시를 기다리는 캐러셀
    var latestStatus: String?       // review / approved / posted
    var updatedAt: Date

    static let appGroup = "group.dev.dechive.jarvis.mobile"
    private static let key = "jarvis.widget.summary.v1"

    var globalFollowers: Int? {
        let parts = [igFollowers, threadsFollowers, facebookFollowers].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    static func load() -> JARVISWidgetSummary? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(JARVISWidgetSummary.self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) {
            UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
        }
    }
}
