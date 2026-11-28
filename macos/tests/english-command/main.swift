import Foundation

@main struct EnglishCommandSmoke {
    static func main() {
        let cases: [(String, String?)] = [
            ("Show stocks", "주식 현황표 보여줘"),
            ("show me the US stocks", "미국 주식 현황 보여줘"),
            ("How's the Korean market?", "국내 주식 현황 보여줘"),
            ("refresh stocks", "주식 현황 갱신해"),
            ("close the stocks", "주식 현황표 닫아"),
            ("What's the weather?", "오늘 날씨 보여줘"),
            ("weather tomorrow in Seoul", "서울내일 날씨 보여줘"),
            ("my schedule", "오늘 일정 보여줘"),
            ("What's on tomorrow?", "내일 일정 보여줘"),
            ("add a new event to my calendar", "일정 추가"),
            ("news briefing", "뉴스 브리핑 보여줘"),
            ("close it", "그 화면 닫아"),
            ("system status", "시스템 상태 보여줘"),
            ("open my projects", "내 프로젝트 열어"),
            ("open the dashboard", nil),          // 기존 영어 대시보드 경로
            ("close the dashboard", nil),
            ("don't show stocks", nil),
            ("I was thinking about how the stock market crashed in 2008 and what it means", nil),
            ("hello how are you", nil),
            ("주식 현황표 보여줘", nil)
        ]
        for (input, want) in cases {
            let got = JarvisEnglishCommand.canonical(input)
            precondition(got == want, "\(input) → \(got ?? "nil"), expected \(want ?? "nil")")
        }
        precondition(JarvisEnglishCommand.canonical("ask Codex to check the weather code") == nil)
        precondition(JarvisEnglishCommand.handoff("Ask Codex to review the voice service code.") ==
                     .init(agent: "codex", task: "review the voice service code"))
        precondition(JarvisEnglishCommand.handoff("have claude summarize today's commits") ==
                     .init(agent: "claude", task: "summarize today's commits"))
        precondition(JarvisEnglishCommand.handoff("코덱스한테 음성 코드 분석 맡겨줘") ==
                     .init(agent: "codex", task: "음성 코드 분석"))
        precondition(JarvisEnglishCommand.handoff("I asked Claude yesterday") == nil)
        precondition(JarvisEnglishCommand.confirmation("Yes.") == true)
        precondition(JarvisEnglishCommand.confirmation("never mind") == false)
        precondition(JarvisEnglishCommand.confirmation("what about tomorrow") == nil)
        // P3 스킬 목록: 모든 스킬은 열기 기준 문장을 갖고, 라우터는 요청처럼 보이는 짧은 문장만 Qwen에 묻는다
        for m in JarvisSkillCatalog.manifests { precondition(m.canonical[.open] != nil && !m.examples.isEmpty, m.id) }
        precondition(JarvisSkillRouter.looksLikeRequest("pull up the market numbers"))
        precondition(JarvisSkillRouter.looksLikeRequest("anything on my agenda"))
        precondition(JarvisSkillRouter.looksLikeRequest("주식 좀 꺼내봐"))
        precondition(!JarvisSkillRouter.looksLikeRequest("how was your day"))
        precondition(!JarvisSkillRouter.looksLikeRequest("I spent the whole afternoon editing the video and I think it finally works now, what do you think about it"))
        precondition(JarvisSkillExamples.normalize("Pull up the MARKET numbers!") == "pull up the market numbers")
        print("PASS: English commands open the existing boards (\(cases.count) cases) + CLI handoff + skill router")
    }
}
