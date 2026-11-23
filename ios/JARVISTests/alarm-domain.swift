import Foundation

@main
struct JARVISAlarmDomainTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23,
                                                        hour: 8, minute: 0))!
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24,
                                                         hour: 8, minute: 0))!
        let oneOff = JARVISAlarmRecord(title: "아침", hour: 7, minute: 30)
        try oneOff.validate()
        guard let next = oneOff.nextFire(after: monday, calendar: calendar) else {
            fatalError("one-shot next occurrence missing")
        }
        precondition(calendar.component(.day, from: next) == 24)
        precondition(calendar.component(.hour, from: next) == 7)
        precondition(calendar.component(.minute, from: next) == 30)
        precondition(oneOff.recurrenceLabel == "한 번만")
        precondition(oneOff.timeLabel == "오전 7:30")

        let weekday = JARVISAlarmRecord(title: "평일 아침", hour: 7, minute: 0,
                                        weekdays: [2,3,4,5,6])
        try weekday.validate()
        precondition(weekday.recurrenceLabel == "평일")
        let friday = JARVISAlarmRecord(title: "금요일", hour: 6, minute: 40,
                                       weekdays: [6])
        guard let nextFriday = friday.nextFire(after: tuesday, calendar: calendar) else {
            fatalError("Friday recurrence missing")
        }
        precondition(calendar.component(.day, from: nextFriday) == 27)
        precondition(calendar.component(.hour, from: nextFriday) == 6)
        precondition(friday.recurrenceLabel == "금요일")

        let saturdayOnly = JARVISAlarmRecord(title: "토요일", hour: 7, minute: 0,
                                            weekdays: [7])
        guard let nextSaturday = saturdayOnly.nextFire(after: tuesday, calendar: calendar) else {
            fatalError("Saturday occurrence missing")
        }
        precondition(calendar.component(.day, from: nextSaturday) == 28)
        let midnight = JARVISAlarmRecord(title: "자정", hour: 0, minute: 5)
        precondition(midnight.timeLabel == "오전 12:05")
        precondition(JARVISAlarmRecord(hour: 12, minute: 15).timeLabel == "오후 12:15")

        for invalid in [
            JARVISAlarmRecord(title: "", hour: 7),
            JARVISAlarmRecord(title: "실패", hour: 24),
            JARVISAlarmRecord(title: "실패", minute: 60),
            JARVISAlarmRecord(title: "중복", weekdays: [2,2]),
            JARVISAlarmRecord(title: "범위", weekdays: [0, 8])
        ] {
            do {
                try invalid.validate()
                fatalError("invalid alarm accepted: \(invalid)")
            } catch is JARVISAlarmError { }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(JARVISAlarmRecord.self, from: encoder.encode(friday))
        precondition(restored.id == friday.id && restored.title == friday.title &&
                     restored.hour == friday.hour && restored.minute == friday.minute &&
                     restored.weekdays == friday.weekdays &&
                     restored.isEnabled == friday.isEnabled)
        print("PASS: 1-shot, weekday recurrence, next Friday and Saturday, 12h format, invalid values, persistence format")
    }
}
