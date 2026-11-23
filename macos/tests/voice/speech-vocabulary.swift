import Foundation

@main struct SpeechVocabularySmoke {
    static func main() {
        let terms=JarvisSpeechVocabulary.phrases
        precondition(!terms.isEmpty && terms.count<=100)
        precondition(Set(terms).count==terms.count)
        precondition(terms.allSatisfy {
            !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty &&
            $0.count<=30 &&
            !$0.contains("\n")
        })
        for item in ["애기야","아기야","자비스","데카이브","DECHIVE","깃허브","GitHub",
                     "Vercel","Ollama","Qwen","ElevenLabs","주식 현황표","토스증권","거래대금 순위","미국 주식 TOP 10","브라우저"] {
            precondition(terms.contains(item),"Missing vocabulary hint: \(item)")
        }
        print("PASS: short, unique and bounded on-device JARVIS speech vocabulary (\(terms.count))")
    }
}
