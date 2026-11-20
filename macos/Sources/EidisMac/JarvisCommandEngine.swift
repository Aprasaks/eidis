import Foundation

/// Explicit, type-checked local action registry. Tool names returned by Qwen
/// never become arbitrary URLs, Swift selectors, shell commands, or file paths.
/// Additional services (GitHub, Notion, Obsidian, Photos) must register their
/// own reviewed executor and permissions before being advertised to the model.
enum JarvisCommand: Equatable {
    case openBrowser(JarvisWebIntent.SearchEngine)
    case searchWeb(String, JarvisWebIntent.SearchEngine)
    case showDashboard
    case summarizePage
    case closePanel(Panel)

    enum Panel: String { case browser, dashboard }

    static let tools: [[String: Any]] = [
        ["type": "function", "function": [
            "name": "open_browser",
            "description": "사용자가 인터넷 창, 웹 브라우저, 네이버/구글 페이지를 열라고 할 때. 검색어가 없어도 호출. 실제로 여는 행위는 JARVIS가 처리한다.",
            "parameters": ["type": "object", "properties": [
                "engine": ["type": "string", "enum": ["naver", "google"]]
            ]]
        ]],
        ["type": "function", "function": [
            "name": "search_web",
            "description": "공개된 웹 정보를 찾아보거나 검색하라는 명령. 개인 파일, 메일, 비공개 메모 내용은 보내면 안 된다. 결과는 JARVIS 내부 브라우저에 표시한다.",
            "parameters": ["type": "object", "properties": [
                "query": ["type": "string", "description": "실제 검색어, 180자 이내"],
                "engine": ["type": "string", "enum": ["naver", "google"]]
            ], "required": ["query"]]
        ]],
        ["type": "function", "function": [
            "name": "show_work_dashboard",
            "description": "JARVIS 내부에 기록된 프로젝트, 할 일, 작업 상태를 보여 달라는 요청. 로컬 DB 읽기 전용.",
            "parameters": ["type": "object", "properties": [:] as [String: Any]]
        ]],
        ["type": "function", "function": [
            "name": "summarize_current_page",
            "description": "현재 JARVIS 내부 브라우저에 열린 실제 웹페이지의 본문을 읽고 출처를 명시해 분석·요약해달라는 요청. 링크 없는 유튜브 영상 자체 분석은 지원하지 않음.",
            "parameters": ["type": "object", "properties": [:] as [String: Any]]
        ]],
        ["type": "function", "function": [
            "name": "close_panel",
            "description": "현재 열린 브라우저/웹 검색창 또는 작업 대시보드를 숨기라는 요청.",
            "parameters": ["type": "object", "properties": [
                "panel": ["type": "string", "enum": ["browser", "dashboard"]]
            ], "required": ["panel"]]
        ]]
    ]

    static let toolNames: Set<String> = ["open_browser", "search_web", "show_work_dashboard", "summarize_current_page", "close_panel"]

    static let systemInstructions = """
    당신은 JARVIS Mac에서 작동하는 한국어 개인 비서의 명령 판단기입니다.
    사용자가 기능 실행을 요청하면 적절한 함수를 반드시 호출하세요. 함수 호출 없이 실행했다고 말하지 마세요.
    '인터넷 좀 켜줘', '네이버 들어가 보자', '구글 열어줘'는 open_browser를 사용하세요.
    '뭐 좀 찾아봐', '웹에서 조사해봐'처럼 검색 요청이면 검색어가 있을 때 search_web을 사용하세요.
    '내 할 일 어디까지 됐어', '프로젝트 상태 보여줘'는 show_work_dashboard를 사용하세요.
    대시보드/검색창을 치워달라고 하면 close_panel을 사용하세요.
    사용자가 현재 브라우저에 열린 페이지 내용을 요약·분석·설명해달라고 하면 summarize_current_page 함수를 호출하세요.
    어떤 페이지가 열려 있는지는 실제 화면 상태를 참고하고, 실행 전 내용을 읽었다고 주장하지 마세요.
    복합 요청은 최대 세 개의 허용된 함수를 필요한 순서대로 호출하세요.
    그냥 대화나 설명을 요청하면 함수를 호출하지 않고 한국어로 간결히 답하세요.
    아직 유튜브 영상 분석, GitHub 저장소 읽기, Notion/Obsidian 편집, 사진 정리, 임의 앱 제어는 연결되지 않았습니다.
    연결되지 않은 기능을 완료했다고 주장하거나 사용자의 허락 없이 개인정보를 검색어로 보내면 안 됩니다.
    실제로 접근하지 않은 데이터나 화면을 봤다고 말하지 마세요.
    당신의 이름은 자비스(JARVIS)이고, 사용자는 데카이브입니다. '저'는 항상 자비스만 가리킵니다.
    사용자의 이름이나 호칭을 부를 때는 항상 '데카이브'라고 발음하고 표현하세요. DECHIVE는 브랜드 영문 표기이며 사람을 부르는 호칭은 '데카이브'입니다.
    사용자의 호칭을 묻는 질문에 '저를 데카이브라고 부르세요'라고 답하지 마세요.
    사용자 자료 보관함은 별도 로컬 명령에서 실제 SQLite 조회 후 응답합니다. 스스로 저장했다고 주장하거나 읽지 않은 자료를 인용하지 마세요.
    일상적인 잡담도 자연스럽게 이어가세요. 직전 사용자 발화와 대화 맥락을 참고해 짧게 반응하되, 매번 판에 박힌 인사나 되묻기로 끝내지 마세요.
    음성 인식 문장이 잘리거나 의미가 불명확하면 임의로 맥락을 채우지 말고 어느 부분이 불명확한지 한 가지를 짧게 확인하세요.
    사실, 수치, 날짜, 현재 상태를 확신할 수 없으면 모른다고 말하고 검증 가능한 근거를 우선하세요. 연결되지 않은 API나 실제로 조회하지 않은 데이터를 추측해 답하지 마세요.
    설명은 핵심 답을 먼저 제시하고, 필요한 경우 한두 가지 이유를 덧붙이세요. 어려운 내용은 차분하게 나누어 설명하되 인위적인 대기 시간을 추가하지 마세요.
    사용자가 도중에 말을 바꾸거나 "아니 그거 말고"라고 하면 새로운 의도를 우선하고, 하지 않은 작업을 했다고 말하지 마세요.
    화법은 한국어로 자연스럽게, 답변은 보통 두세 문장 이내로 해주세요.
    """

    static func actions(from message: [String: Any], utterance: String) -> [Self]? {
        guard let calls = message["tool_calls"] as? [[String: Any]], !calls.isEmpty else { return nil }
        // Reject the whole plan if any part is unknown or malformed.
        guard calls.count <= 3 else { return [] }
        var actions: [Self] = []
        for call in calls {
            guard let function = call["function"] as? [String: Any],
                  let name = function["name"] as? String, toolNames.contains(name) else { return [] }
            var args = function["arguments"] as? [String: Any] ?? [:]
            if let raw = function["arguments"] as? String,
               let data = raw.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                args = parsed
            }
            let requestedEngine: JarvisWebIntent.SearchEngine =
                utterance.localizedCaseInsensitiveContains("구글") ||
                utterance.localizedCaseInsensitiveContains("google") ? .google : .naver
            switch name {
            case "open_browser":
                actions.append(.openBrowser(requestedEngine))
            case "search_web":
                guard let query = args["query"] as? String else { return [] }
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty && trimmed.count <= 180 &&
                      isSafePublicSearch(utterance, query: trimmed) else { return [] }
                actions.append(.searchWeb(trimmed, requestedEngine))
            case "show_work_dashboard":
                actions.append(.showDashboard)
            case "summarize_current_page":
                actions.append(.summarizePage)
            case "close_panel":
                guard let panelName = args["panel"] as? String,
                      let panel = Panel(rawValue: panelName) else { return [] }
                actions.append(.closePanel(panel))
            default: return []
            }
        }
        return actions
    }

    /// Public search must not silently leak private local context to a provider.
    static func isSafePublicSearch(_ utterance: String, query: String) -> Bool {
        let input = (utterance + " " + query).lowercased().replacingOccurrences(of: " ", with: "")
        let prohibited = ["내파일", "맥파일", "내문서", "로컬파일", "파일찾아", "내프로젝트",
                          "내작업", "작업기록", "내메일", "이메일에서", "메일에서",
                          "다운로드폴더", "내사진", "사진폴더", "내노션", "내옵시디언",
                          "/users/", "~/", "apikey", "api키", "비밀번호", "패스워드"]
        if prohibited.contains(where: { input.contains($0) }) { return false }
        if query.contains("@") || query.contains("\n") || query.contains("\r") { return false }
        return true
    }

    static func directPageSummaryIntent(_ phrase: String) -> Bool {
        let text = phrase.lowercased().replacingOccurrences(of: " ", with: "")
        let page = ["이페이지", "이웹페이지", "현재페이지", "지금페이지", "이사이트", "이기사",
                    "지금보는페이지", "열린페이지", "여기내용", "이화면내용", "이글"].contains {
            text.contains($0)
        }
        let operation = ["요약", "분석", "설명", "정리", "알려줘", "핵심"].contains { text.contains($0) }
        return page && operation
    }

    /// No-model safety net for very clear high-frequency commands when the
    /// locally run model responds in text rather than selecting a tool.
    static func directFallback(for phrase: String) -> [Self]? {
        let s = phrase.lowercased().replacingOccurrences(of: " ", with: "")
        if ["인터넷", "브라우저", "네이버", "구글", "google"].contains(where: { s.contains($0) }) &&
           ["열어", "켜", "들어가", "띄워", "접속"].contains(where: { s.contains($0) }) &&
           !["파일", "문서", "메일", "프로젝트", "검색", "찾아"].contains(where: { s.contains($0) }) {
            return [.openBrowser(s.contains("구글") || s.contains("google") ? .google : .naver)]
        }
        if let web = JarvisWebIntent.parse(phrase) {
            switch web {
            case .hide: return [.closePanel(.browser)]
            case .search(let query, let engine):
                if isSafePublicSearch(phrase, query: query) { return [.searchWeb(query, engine)] }
            }
        }
        if directPageSummaryIntent(phrase) { return [.summarizePage] }
        if let dashboard = JarvisDashboardIntent.parse(phrase) {
            switch dashboard {
            case .show: return [.showDashboard]
            case .hide: return [.closePanel(.dashboard)]
            }
        }
        return nil
    }
}
