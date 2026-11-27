import Foundation

/// 자비스 대화 언어 (2026-11-27 사용자 결정: 영어). UserDefaults "jarvis.conversation.language" = "en" | "ko".
/// 한국어 동작은 지우지 않고 설정으로 되돌릴 수 있게 둔다.
enum JarvisConversationLanguage {
    static var english: Bool { UserDefaults.standard.string(forKey: "jarvis.conversation.language") != "ko" }

    /// 음성 인식 언어
    static var speechLocale: Locale { Locale(identifier: english ? "en-US" : "ko-KR") }

    /// 대화 시스템 프롬프트의 맨 끝에 붙는 최종 규칙 (앞의 한국어 지침보다 우선).
    static var finalDirective: String {
        guard english else { return "" }
        return """

        [FINAL LANGUAGE RULE — overrides any earlier instruction about language or address]
        Always reply in natural, concise English as JARVIS: calm, warm, quietly witty, like a capable personal assistant.
        Do not use Korean in replies, even if earlier instructions or the user's message are in Korean.
        Do not use the Korean address '오빠'. Usually answer in one to three short sentences; no emojis, no markdown.
        All earlier rules about honesty, memory, approvals and not inventing facts still apply.
        """
    }

    static var summonGreeting: String { english ? "Welcome back. How can I help?" : "오빠, 뭘 도와드릴까요?" }
    static var wakeAcknowledgment: String { english ? "Yes?" : "네 오빠" }
}
