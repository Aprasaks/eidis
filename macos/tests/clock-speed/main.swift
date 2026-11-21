import Foundation

@main struct LocalClockAndRoutingSmoke {
    static func main() {
        precondition(JarvisLocalClock.parse("자비스, 오늘은 무슨 요일이야?") == .date)
        precondition(JarvisLocalClock.parse("자비스 오늘 날짜는?") == .date)
        precondition(JarvisLocalClock.parse("오늘이 몇 월 몇 일이야?") == .date)
        precondition(JarvisLocalClock.parse("오늘은 몇 월 며칠이야") == .date)
        precondition(JarvisLocalClock.parse("지금 몇 시야?") == .time)
        precondition(JarvisLocalClock.parse("현재 시간 알려줘") == .time)
        precondition(JarvisLocalClock.parse("오늘 날짜와 시간 알려줘") == .both)
        precondition(JarvisLocalClock.parse("오늘 프로젝트 상태 보여줘") == nil)
        precondition(JarvisLocalClock.parse("오늘 무슨 일을 할까?") == nil)
        precondition(JarvisLocalClock.parse("오늘 날짜 검색해줘") == nil)
        precondition(JarvisLocalClock.parse("자비스, 오늘 날짜 말하지 마") == nil)
        let zone=TimeZone(identifier:"Asia/Seoul")!
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=zone
        let fixed=calendar.date(from: DateComponents(year:2026,month:11,day:21,hour:19,minute:30))!
        let date=JarvisLocalClock.answer(.date,now:fixed,zone:zone)
        let time=JarvisLocalClock.answer(.time,now:fixed,zone:zone)
        precondition(date.contains("2026년 11월 21일 토요일"),"Bad date: \(date)")
        precondition(time.contains("7시 30분"),"Bad time: \(time)")
        precondition(date.contains("Asia/Seoul"),"Missing zone: \(date)")
        let now=Date()
        let live=JarvisLocalClock.answer(.date,now:now)
        print("MAC_CLOCK:",live)
        let actual=Calendar(identifier:.gregorian).dateComponents(in:.current,from:now)
        precondition(live.contains("\(actual.year!)년 \(actual.month!)월 \(actual.day!)일"),
                     "Mac date mismatch: \(live)")
        for prompt in ["안녕, 자비스","오늘 기분 어때?","생각이란 뭘까?","어떻게 생각해?"] {
            precondition(JarvisConversationSpeedRoute.shouldStreamWithoutTools(prompt))
        }
        for prompt in ["브라우저 열어줘","깃허브 프로젝트 현황 보여줘",
                       "오늘 날짜 검색해줘","이 페이지 요약해줘","유튜브 업로드 해줘",
                       "현재 날씨 알려줘","내 자료 보관함 열어줘","파일 저장해줘"] {
            precondition(!JarvisConversationSpeedRoute.shouldStreamWithoutTools(prompt),prompt)
        }
        print("PASS: real local date, explicit date intents, chat streaming/tool execution separation")
    }
}
