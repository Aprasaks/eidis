import Foundation

/// 영어 명령 → 이미 있는 화면을 여는 한국어 명령 (2026-11-28 사용자 요청: 새 대시보드를 만들지 말고 있는 화면을 열 것).
///
/// 맥 이디스는 영어로 대화한다. 주식·날씨·일정·뉴스 브리핑 같은 화면의 명령 판별은 한국어 문장으로
/// 만들어져 있어서, 짧은 영어 명령만 같은 뜻의 한국어 명령으로 바꿔 기존 경로를 그대로 탄다.
/// 긴 문장, 부정문("don't"), 화면과 상관없는 말은 nil → 평소처럼 Qwen 대화로 간다.
enum JarvisEnglishCommand {
    static func canonical(_ raw: String) -> String? {
        var s = raw.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9' ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count <= 70, s.range(of: #"[a-z]"#, options: .regularExpression) != nil else { return nil }
        for filler in ["please ", "can you ", "could you ", "would you ", "hey ", "eidis ", "edith ", "jarvis "] where s.hasPrefix(filler) {
            s.removeFirst(filler.count)
        }
        s = " " + s + " "
        func any(_ words: [String]) -> Bool { words.contains { s.contains($0) } }
        guard !any([" don't ", " dont ", " do not ", " never ", " not "]) else { return nil }

        let close = any([" close ", " hide ", " turn off ", " dismiss ", " put away ", " shut "])
        let refresh = any([" refresh ", " update ", " reload "])
        let stock = any([" stock", " stocks ", " market ", " markets ", " shares ", " kospi ", " nasdaq ", " tickers "])
        let weather = any([" weather ", " forecast ", " temperature "])
        let calendar = any([" schedule ", " calendar ", " agenda ", " events ", " appointments ", " what's on ", " whats on "])
        let news = any([" news ", " briefing ", " headlines "])
        let projects = any([" projects ", " project status ", " my project "])
        let system = any([" system status ", " eidis status ", " server status ", " diagnostics "])
        let knowledge = any([" knowledge ", " saved items ", " archive ", " my notes "])
        let tomorrow = any([" tomorrow "])
        let week = any([" this week ", " week ", " weekly "])

        if close {
            if stock { return "주식 현황표 닫아" }
            if weather { return "날씨 닫아" }
            if calendar { return "일정 닫아" }
            if news { return "브리핑 닫아" }
            if any([" it ", " that ", " this ", " panel ", " screen ", " window "]) { return "그 화면 닫아" }
            return nil   // "close the dashboard" 등은 기존 영어 처리(JarvisLiveDashboardIntent)가 맡는다
        }
        if stock {
            if refresh { return "주식 현황 갱신해" }
            if any([" us ", " u s ", " american ", " nasdaq ", " wall street ", " america "]) { return "미국 주식 현황 보여줘" }
            if any([" korea", " kospi ", " domestic "]) { return "국내 주식 현황 보여줘" }
            return "주식 현황표 보여줘"
        }
        if weather {
            let town = [("seoul", "서울"), ("gunsan", "군산"), ("goyang", "고양")].first { s.contains(" " + $0.0) }?.1 ?? ""
            if any([" hourly ", " by the hour "]) { return town + "시간별 예보 보여줘" }
            if week { return town + "주간 날씨 보여줘" }
            return town + (tomorrow ? "내일 날씨 보여줘" : "오늘 날씨 보여줘")
        }
        if calendar {
            if any([" add ", " new ", " create ", " make "]) { return "일정 추가" }
            if tomorrow { return "내일 일정 보여줘" }
            if week { return "이번주 일정 보여줘" }
            return "오늘 일정 보여줘"
        }
        if news { return "뉴스 브리핑 보여줘" }
        if system { return "시스템 상태 보여줘" }
        if projects { return "내 프로젝트 열어" }
        if knowledge { return "지식 현황 보여줘" }
        return nil
    }

    /// 화면이 돌려준 한국어 안내문을 영어로 바꾼다 (로컬 Qwen · 외부 API 없음). 숫자·이름은 그대로 둔다.
    static func toEnglish(_ korean: String) async -> String? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let system = """
        You are EIDIS, DECHIVE's personal assistant. Rewrite the message below as natural, concise spoken English for DECHIVE.
        Keep every number, price, percentage, time, date, place, company and ticker exactly as written.
        If it is long, keep only the most important points in at most three sentences.
        Do not add anything that is not in the message. Output only the English text, no Korean, no markdown.
        """
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": JarvisLocalModelConfiguration.selectedModel,
            "messages": [["role": "system", "content": system], ["role": "user", "content": String(korean.prefix(2_500))]],
            "stream": false, "think": false, "keep_alive": JarvisLocalModelConfiguration.keepAlive,
            "options": ["num_ctx": JarvisLocalModelConfiguration.contextLength, "num_predict": 260, "temperature": 0.2]
        ] as [String: Any])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty, content.range(of: #"\p{Hangul}"#, options: .regularExpression) == nil else { return nil }
        return content
    }
}
