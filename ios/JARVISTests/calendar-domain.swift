import Foundation

@main
struct CalendarDomainTests {
    static func main() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 9, minute: 0))!
        func parsed(_ input: String, _ expectedTitle: String, _ offsetDays: Int, _ hour: Int, _ minute: Int = 0) {
            guard let result = JARVISCalendarSpeechParser.parse(input, now: now, calendar: cal) else {
                fatalError("Expected parse: \(input)")
            }
            let expectedDay = cal.date(byAdding: .day, value: offsetDays, to: now)!
            precondition(cal.isDate(result.startAt, inSameDayAs: expectedDay), "wrong day for \(input)")
            precondition(cal.component(.hour, from: result.startAt) == hour, "wrong hour for \(input)")
            precondition(cal.component(.minute, from: result.startAt) == minute, "wrong minute for \(input)")
            precondition(result.title == expectedTitle, "wrong title [\(result.title)] for \(input)")
            precondition(result.endAt == nil, "Unstated end time must remain unknown")
        }
        parsed("자비스 내일 오후 3시에 회의 잡아줘", "회의", 1, 15)
        parsed("금요일 오후 2시에 미팅 잡아줘", "미팅", 3, 14)
        parsed("11월 28일 오전 10시에 촬영 일정 등록해줘", "촬영", 4, 10)
        parsed("내일 15시 30분에 회의 추가해줘", "회의", 1, 15, 30)
        parsed("모레 저녁 7시에 저녁 모임 잡아줘", "저녁 모임", 2, 19)
        for input in ["내일 3시에 회의 잡아줘", "오늘 일정 보여줘", "회의 하나 추가해줘", "내일 오후 25시에 회의 등록해줘", "11월 31일 오후 3시에 미팅 잡아줘", "내일 오후 3시에 잡아줘"] {
            precondition(JARVISCalendarSpeechParser.parse(input, now: now, calendar: cal) == nil,
                         "Rejected ambiguous input accepted: \(input)")
        }
        let begin = cal.date(byAdding: .day, value: 2, to: now)!
        let first = JARVISCalendarRecord(title: "미팅", startAt: begin, endAt: begin.addingTimeInterval(3600))
        let second = JARVISCalendarRecord(title: "다른 미팅", startAt: begin.addingTimeInterval(1800), endAt: begin.addingTimeInterval(5400))
        try first.validate()
        try second.validate()
        precondition(first.overlaps(second))
        let invalid = JARVISCalendarRecord(title: "", startAt: begin, endAt: begin)
        do { try invalid.validate(); fatalError("Invalid entry accepted") }
        catch is JARVISCalendarError { }
        let data = try JSONEncoder().encode([first])
        let restored = try JSONDecoder().decode([JARVISCalendarRecord].self, from: data)
        precondition(restored == [first], "JSON identity or timing mismatch")
        print("PASS: 5 accepted speech schedules, 6 ambiguous rejections, overlap, validation, JSON round-trip")
    }
}
