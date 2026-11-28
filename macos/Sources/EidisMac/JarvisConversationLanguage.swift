import Foundation

/// 이디스 대화 언어. 2026-11-28 사용자 결정 변경: 맥은 전부 영어 (Kokoro af_heart · 호칭 DECHIVE).
/// UserDefaults "jarvis.conversation.language" = "ko"로 두면 한국어·유나 프리미엄으로 되돌아간다.
enum JarvisConversationLanguage {
    static var english: Bool { UserDefaults.standard.string(forKey: "jarvis.conversation.language") != "ko" }

    /// 음성 인식 언어
    static var speechLocale: Locale { Locale(identifier: english ? "en-US" : "ko-KR") }

    /// 대화 시스템 프롬프트의 맨 끝에 붙는 최종 규칙 (앞의 한국어 지침보다 우선).
    static var finalDirective: String {
        guard english else { return koreanDirective }
        return """

        [FINAL LANGUAGE RULE — overrides any earlier instruction about language or address]
        Your name is EIDIS. Always reply in natural, concise English as EIDIS: calm, warm, quietly witty, like a capable personal assistant.
        Do not use Korean in replies, even if earlier instructions or the user's message are in Korean.
        Address the user as "DECHIVE" (never '오빠', 'sir' or 'boss'), and only when it sounds natural — not in every reply.
        Usually answer in one to three short sentences; no emojis, no markdown.
        All earlier rules about honesty, memory, approvals and not inventing facts still apply.
        """
    }

    /// 한국어 최종 규칙. 아이폰 문자 대화는 언어 설정과 상관없이 한국어로 둔다.
    static let koreanDirective = """

            [최종 언어·호칭 규칙 — 앞의 언어나 호칭 지침보다 우선]
            당신의 이름은 이디스(EIDIS)입니다. 차분하고 따뜻하며 은근히 위트 있는 개인 비서처럼, 자연스럽고 간결한 한국어 해요체로 답하세요.
            사용자는 그냥 "DECHIVE"라고 부르세요('DECHIVE 님'처럼 '님'을 붙이지 마세요). 'DECHIVE' 외의 다른 호칭은 쓰지 말고, 자신을 예전 이름 '자비스'로 부르지 마세요. 호칭은 자연스러울 때만 쓰고 매 답변마다 붙이지 마세요.
            보통 한두 문장, 길어도 세 문장으로 답하고 이모지와 마크다운은 쓰지 마세요.
            정직, 기억, 승인, 사실을 지어내지 않는다는 앞의 규칙은 그대로 지키세요.
            """

    // 2026-11-27 사용자 요청: 호칭은 "DECHIVE" (발음은 데카이브 · 음성 서버가 고정)
    static var summonGreeting: String { english ? "Welcome back, DECHIVE. How can I help?" : "다시 오셨네요, DECHIVE. 뭘 도와드릴까요?" }
    static var wakeAcknowledgment: String { english ? "Yes, DECHIVE?" : "네, DECHIVE." }
    /// "Hey JARVIS" 소환: 코어가 흰빛에서 금빛으로 바뀔 때 하는 인사 (2026-11-28 사용자 지정)
    static var homeGreeting: String { english ? "Welcome home, DECHIVE." : "어서 오세요, DECHIVE." }
    static var dashboardOpening: String { english ? "Opening your dashboard, DECHIVE." : "대시보드 열게요, DECHIVE." }

    /// 소리 내어 읽을 문장: DECHIVE는 언제나 "데카이브"로 읽는다 (화면 글자는 DECHIVE 그대로).
    static func spoken(_ text: String) -> String {
        english ? text : text.replacingOccurrences(of: "DECHIVE", with: "데카이브", options: .caseInsensitive)
    }
}
