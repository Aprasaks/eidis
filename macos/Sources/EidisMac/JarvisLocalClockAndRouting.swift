import Foundation

/// Local system clock is the source of truth for "today / weekday / current time".
/// No LLM, network, project notes or previously cached chat replies are used.
enum JarvisLocalClock {
    enum Intent: Equatable { case date, time, both }

    static func parse(_ utterance: String) -> Intent? {
        let withoutWake = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(자비스|jarvis)[,，.!！?？\s]*"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
            .lowercased()
        let clean=withoutWake.replacingOccurrences(of: #"[ \t\n\r.!,，?？!！]+"#,
                                                    with: "", options: .regularExpression)
        if Set(["오늘은무슨요일이야","오늘무슨요일이야","오늘무슨요일",
                "오늘은무슨요일","오늘요일","오늘요일은","오늘의요일",
                "지금무슨요일이야","지금무슨요일","오늘이무슨요일이야",
                "오늘이몇월며칠이야","오늘몇월며칠","오늘은몇월며칠",
                "오늘은몇월며칠이야","오늘며칠이야","오늘며칠",
                "오늘날짜","오늘날짜는","오늘날짜뭐야","오늘날짜알려줘",
                "오늘의날짜","오늘이몇일이야","지금날짜","지금날짜알려줘",
                "현재날짜","현재날짜알려줘","올해몇년도야","올해몇년이야",
                "오늘이몇월몇일이야","오늘몇월몇일이야"]).contains(clean) {
            return .date
        }
        if Set(["지금몇시야","현재몇시야","지금몇시","지금몇시인지알려줘",
                "지금시간","지금시간알려줘","현재시간","현재시간알려줘",
                "지금몇시몇분","지금몇시몇분이야","몇시야","지금시각",
                "현재시각"]).contains(clean) { return .time }
        if Set(["오늘날짜와시간","오늘날짜와시간알려줘",
                "지금날짜와시간","현재날짜와시간",
                "지금몇월몇일몇시야","날짜랑시간알려줘"]).contains(clean) {
            return .both
        }
        return nil
    }

    static func context(now:Date=Date(),zone:TimeZone = .current) -> String {
        let formatter=DateFormatter()
        formatter.locale=Locale(identifier:"en_US_POSIX")
        formatter.calendar=Calendar(identifier:.gregorian)
        formatter.timeZone=zone
        formatter.dateFormat="yyyy-MM-dd HH:mm Z"
        return formatter.string(from:now)
    }

    static func answer(_ intent: Intent, now: Date = Date(),
                       zone: TimeZone = .current) -> String {
        let formatter=DateFormatter()
        formatter.calendar=Calendar(identifier: .gregorian)
        formatter.timeZone=zone
        formatter.locale=Locale(identifier:"ko_KR")
        let result: String
        switch intent {
        case .date:
            formatter.dateFormat="yyyy년 M월 d일 EEEE"
            result=formatter.string(from:now)
        case .time:
            formatter.dateFormat="a h시 m분"
            result=formatter.string(from:now)
        case .both:
            formatter.dateFormat="yyyy년 M월 d일 EEEE a h시 m분"
            result=formatter.string(from:now)
        }
        let label=zone.abbreviation(for: now) ?? zone.identifier
        return "주인님, Mac 시스템 시각 기준 \(result)입니다. (\(zone.identifier), \(label))"
    }
}

/// Strip only an explicit standalone addressing prefix, never DECHIVE or
/// a substring of an ordinary word. Preserve the original transcript in UI.
enum JarvisDialogueInput {
    static func command(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(데카|자비스|jarvis)(?=$|[\s,，.!！?？])[,，.!！?？\s]*"#,
                                  with: "", options: [.regularExpression,.caseInsensitive])
    }
    static func asksTodayTasks(_ text: String) -> Bool {
        let compact = command(text).filter { !$0.isWhitespace }.trimmingCharacters(in: CharacterSet(charactersIn: ".!?？!！요"))
        return ["오늘할일", "오늘할일알려줘", "오늘할일뭐야", "오늘할일보여줘",
                "오늘해야할일", "오늘해야할일알려줘", "오늘뭐해야돼", "오늘뭐해야해",
                "오늘할일이뭐야", "오늘할일정리해줘"].contains(compact)
    }
}

/// Conservative routing: action-like language retains the existing audited
/// tool registry. Ordinary conversation can stream without invoking a tool
/// selector, making the first visible answer appear sooner.
enum JarvisConversationSpeedRoute {
    static func shouldStreamWithoutTools(_ utterance: String) -> Bool {
        let compact=utterance.lowercased().replacingOccurrences(of:" ",with:"")
        if compact.isEmpty || compact.count>500 { return false }
        let actionTriggers=[
            "브라우저","웹에서","웹검색","사이트","페이지",
            "네이버","구글","google","github","깃허브","vercel",
            "검색","조회","수집","조사","현황","대시보드",
            "저장","기억","기록","수정","삭제","변경","추가",
            "실행","조작","클릭","전송","발행","게시","설정",
            "열어","켜줘","켜봐","띄워","닫아","꺼줘","접속",
            "보여줘","보여줄","화면","링크","파일","폴더",
            "작업","프로젝트","유튜브","youtube",
            "일정","캘린더","메일","이메일","날씨","실시간",
            "재생","업로드","다운로드","배포","종료",
            "자동화","접근","결제","구매","스크롤",
            "외부","내컴퓨터","내맥","내부기억","내자료","내정보"
        ]
        return !actionTriggers.contains(where: {compact.contains($0)})
    }
}
