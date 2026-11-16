import Foundation

/// Local, deterministic voice command routing. "애기야" is an invocation
/// phrase inside a user-started microphone session, not an always-on wake word.
enum EIDISIntent: Equatable {
    case greeting
    case weather
    case calendar
    case reminders
    case help
    case unsupported
    case unknown
}

enum EIDISCommand {
    static let hints = [
        "애기야", "아기야", "애기",
        "애기야 안녕", "애기야 날씨 알려줘",
        "애기야 오늘 일정", "애기야 오늘 할 일",
        "애기야 미리 알림 보여줘", "애기야 뭐 할 수 있어"
    ]

    static func intent(for text: String) -> EIDISIntent {
        // Whitespace and punctuation are common Korean STT variations.
        let normalized = String(text.lowercased().filter {
            !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol
        })
        guard !normalized.isEmpty else { return .unknown }

        if containsAny(normalized, ["날씨", "기온", "온도", "비와", "춥", "덥"]) {
            return .weather
        }
        if containsAny(normalized, ["미리알림", "리마인더", "할일", "해야할일",
                                    "할것", "작업목록", "체크리스트"]) {
            return .reminders
        }
        if containsAny(normalized, ["일정", "약속", "캘린더", "스케줄", "회의"]) {
            return .calendar
        }
        if containsAny(normalized, ["뭘할수", "뭐할수", "무엇을할수", "기능", "사용법"]) {
            return .help
        }
        if containsAny(normalized, ["프로젝트", "자비스기억", "화면분석", "사물인식",
                                    "길안내", "지도"]) {
            return .unsupported
        }

        if containsAny(normalized, ["애기야", "아기야", "애기", "이디스", "자비스",
                                    "안녕", "좋은아침", "좋은오후"]) {
            return .greeting
        }
        return .unknown
    }

    private static func containsAny(_ input: String, _ needles: [String]) -> Bool {
        needles.contains(where: input.contains)
    }
}
