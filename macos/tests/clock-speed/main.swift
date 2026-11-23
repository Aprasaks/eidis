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
        precondition(JarvisLocalClock.context(now:fixed,zone:zone) == "2026-11-21 19:30 +0900")
        precondition(JarvisDialogueInput.command("애기야, 오늘 날씨 어때?") == "오늘 날씨 어때?")
        precondition(JarvisDialogueInput.command("아기야 오늘 날짜 알려줘") == "오늘 날짜 알려줘")
        precondition(JarvisDialogueInput.command("애기야말로 중요해") == "애기야말로 중요해")
        precondition(JarvisDialogueInput.personalWakeGreeting("애기야")?.reply == "네 오빠")
        precondition(JarvisDialogueInput.personalWakeGreeting(" 애기야! ")?.reply == "네 오빠")
        precondition(JarvisDialogueInput.personalWakeGreeting("아기야?")?.reply == "네 오빠")
        precondition(JarvisDialogueInput.personalWakeGreeting("애기야 오늘 날씨 알려줘") == nil)
        precondition(JarvisDialogueInput.personalWakeGreeting("애기야말로") == nil)
        precondition(JarvisDialogueInput.personalWakeGreeting("자비스") == nil)
        precondition(JarvisDialogueInput.command("데카, 오늘 날씨 어때?") == "오늘 날씨 어때?")
        precondition(JarvisDialogueInput.command("데카?").isEmpty)
        precondition(JarvisDialogueInput.command("데카이브 프로젝트") == "데카이브 프로젝트")
        precondition(JarvisDialogueInput.asksTodayTasks("자비스 오늘 할일 알려줘"))
        precondition(JarvisDialogueInput.asksTodayTasks("데카, 오늘 할 일 뭐야?"))
        precondition(!JarvisDialogueInput.asksTodayTasks("오늘 할 일 알려주지 마"))
        for input in ["자비스 깨어 있어?", "데카, 거기 있어?", "듣고 있어?", "잘 들려?"] {
            precondition(JarvisDialogueInput.presenceOrEnd(input)?.end == false)
        }
        for input in ["데카, 이제 쉬어", "이제 대기해", "나중에 이야기하자"] {
            precondition(JarvisDialogueInput.presenceOrEnd(input)?.end == true)
        }
        precondition(JarvisDialogueInput.presenceOrEnd("오늘 날씨 어때?") == nil)
        precondition(JarvisDialogueInput.presenceOrEnd("프로그램 대기해") == nil)
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
