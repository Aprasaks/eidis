import Foundation

@main struct TestLiveDashboardIntent {
    static func main() {
        let overview = [
            "대시보드 열어봐", "대시보드 열어줘", "대시보드 좀 열어봐",
            "자비스, 대시보드 열어봐", "애기야 대시보드 열어봐",
            "현황 열어줘", "현황 좀 열어봐", "실시간 현황 열어봐",
            "실시간 보드 열어봐", "실시간 보드 보여줘", "실시간 대시보드 열어봐", "라이브 보드 띄워줘",
            "전체 대시보드 열어줘", "전체 현황 열어봐", "관제실 열어줘",
        ]
        for phrase in overview {
            precondition(JarvisLiveDashboardIntent.parse(phrase) == .show(.overview),
                         "Not routed to overview: \(phrase)")
        }
        let specific: [(String, JarvisLiveDashboardIntent)] = [
            ("프로젝트 현황 열어줘", .show(.projects)),
            ("저장 자료 분석 보여줘", .show(.knowledge)),
            ("시스템 상태 보여줘", .show(.system)),
            ("전체 대시보드 닫아", .hide),
            ("대시보드 꺼줘", .hide),
            ("유튜브 현황 보여줘", .show(.overview)),
        ]
        for (phrase, expected) in specific {
            precondition(JarvisLiveDashboardIntent.parse(phrase) == expected,
                         "Regressed existing intent: \(phrase)")
        }
        for phrase in ["안녕", "현황이 좋네", "현황이 왜 이래", "웹사이트 열어줘"] {
            precondition(JarvisLiveDashboardIntent.parse(phrase) == nil,
                         "False positive: \(phrase)")
        }
        print("PASS: \(overview.count) colloquial openings, \(specific.count) existing commands, 4 non-commands")
    }
}
