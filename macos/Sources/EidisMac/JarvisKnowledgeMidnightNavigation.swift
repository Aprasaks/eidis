import Foundation

/// Screen navigation only. Does not launch Codex, call Sanity or wake a Mac.
enum JarvisKnowledgeMidnightNavigation {
    static let lastOpenedDayKey = "jarvis.knowledge.midnight.lastOpenedKSTDay.v1"

    static func dueDay(at date: Date, lastOpenedDay: String?, overviewVisible: Bool, projectAlreadyOpen: Bool) -> String? {
        guard overviewVisible, !projectAlreadyOpen else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "Asia/Seoul") else { return nil }
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        // A narrow window prevents a late catch-up from interrupting daytime work.
        guard parts.hour == 0, parts.minute == 0,
              let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
        guard lastOpenedDay != dayKey else { return nil }
        return dayKey
    }
}
