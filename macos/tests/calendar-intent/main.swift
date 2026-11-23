import Foundation

@main
struct CalendarMacIntentSmoke {
    static func main() {
        precondition(JarvisMacCalendarIntent.parse("자비스, 일정 보여줘") == .show)
        precondition(JarvisMacCalendarIntent.parse("자비스, 캘린더 열어봐") == .show)
        precondition(JarvisMacCalendarIntent.parse("내일 오후 3시에 회의 잡아줘") == .new)
        precondition(JarvisMacCalendarIntent.parse("일정 추가해줘") == .new)
        precondition(JarvisMacCalendarIntent.parse("일정 닫아줘") == .hide)
        precondition(JarvisMacCalendarIntent.parse("오늘 날씨") == nil)
        precondition(JarvisMacCalendarIntent.parse("회의는 왜 길어질까") == nil)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 10))!
        guard let proposal = JarvisMacCalendarDraft.extract("자비스, 내일 오후 3시에 회의 잡아줘", now: now, calendar: cal) else {
            fatalError("Calendar proposal parser did not produce a draft")
        }
        precondition(proposal.title == "회의", "Wrong title: \(proposal.title)")
        precondition(cal.component(.day, from: proposal.start) == 25)
        precondition(cal.component(.hour, from: proposal.start) == 15)
        precondition(JarvisMacCalendarDraft.extract("내일 3시에 미팅 등록해줘", now: now, calendar: cal) == nil)
        precondition(JarvisMacCalendarDraft.extract("11월 31일 오후 3시에 회의 잡아줘", now: now, calendar: cal) == nil)
        guard let explicit = JarvisMacCalendarDraft.extract("2026년 11월 27일 오전 9시에 촬영 등록해줘", now: now, calendar: cal) else {
            fatalError("Absolute date proposal parser did not work")
        }
        precondition(explicit.title == "촬영", "Wrong explicit title: \(explicit.title)")
        precondition(cal.component(.day, from: explicit.start) == 27)
        precondition(cal.component(.hour, from: explicit.start) == 9)
        print("JARVIS Mac calendar command/parser tests OK")
    }
}
