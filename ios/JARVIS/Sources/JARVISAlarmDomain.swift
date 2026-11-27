import Foundation

/// User-owned JARVIS alarm specification, separate from Apple Clock and Calendar.
struct JARVISAlarmRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var hour: Int
    var minute: Int
    /// Gregorian weekday numbers (Sunday=1, Monday=2 ... Saturday=7).
    /// Empty array means the *next* occurrence, exactly once.
    var weekdays: [Int]
    var isEnabled: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String = "좋은 아침이에요, DECHIVE",
         hour: Int = 7, minute: Int = 0, weekdays: [Int] = [],
         isEnabled: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    func validate() throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw JARVISAlarmError.invalid("시간이 올바르지 않아요.")
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle.count <= 60 else {
            throw JARVISAlarmError.invalid("알람 이름은 1~60자로 입력해 주세요.")
        }
        guard weekdays.count == Set(weekdays).count,
              weekdays.allSatisfy({ (1...7).contains($0) }) else {
            throw JARVISAlarmError.invalid("반복 요일을 다시 확인해 주세요.")
        }
    }

    func nextFire(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let matching = DateComponents(hour: hour, minute: minute, second: 0)
        guard let next = calendar.nextDate(after: now, matching: matching,
                                           matchingPolicy: .nextTime,
                                           repeatedTimePolicy: .first,
                                           direction: .forward) else { return nil }
        if weekdays.isEmpty { return next }

        // Compare Gregorian user-selected weekdays to local calendar weekdays.
        for offset in 0...7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: next),
                  let occurrence = calendar.nextDate(after: date.addingTimeInterval(-1),
                    matching: matching, matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first, direction: .forward) else { continue }
            if weekdays.contains(calendar.component(.weekday, from: occurrence)) {
                return occurrence
            }
        }
        return nil
    }

    var timeLabel: String {
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%@ %d:%02d", hour < 12 ? "오전" : "오후", hour12, minute)
    }

    var recurrenceLabel: String {
        guard !weekdays.isEmpty else { return "한 번만" }
        if Set(weekdays) == Set(1...7) { return "매일" }
        if Set(weekdays) == Set(2...6) { return "평일" }
        if Set(weekdays) == Set([1, 7]) { return "주말" }
        let names = [1: "일", 2: "월", 3: "화", 4: "수", 5: "목",
                     6: "금", 7: "토"]
        return weekdays.sorted().compactMap { names[$0] }.joined(separator: "·") + "요일"
    }
}

enum JARVISAlarmError: LocalizedError {
    case invalid(String)
    case storage(String)
    case unsupported
    case denied
    case system(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .storage(let message), .system(let message):
            message
        case .unsupported:
            "이디스 알람은 iOS 26 이상에서 사용할 수 있어요."
        case .denied:
            "알람 권한이 필요해요. iPhone 설정에서 EIDIS의 알람 접근을 허용해 주세요."
        }
    }
}
