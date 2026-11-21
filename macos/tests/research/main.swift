import Foundation

@main struct ResearchSmoke {
    static func main() {
        precondition(JarvisResearchIntent.parse("자비스, DECHIVE 홍보 플랫폼 조사해줘") == .submit("DECHIVE 홍보 플랫폼"))
        precondition(JarvisResearchIntent.parse("자비스, 파이썬 공식 문서 웹에서 조사해줘") == .submit("파이썬 공식 문서"))
        precondition(JarvisResearchIntent.parse("자비스, 조사 현황 알려줘") == .status)
        precondition(JarvisResearchIntent.parse("자비스, 조사 보고서 3번 보여줘") == .report(3))
        precondition(JarvisResearchIntent.parse("자비스, 조사 2번 중단해") == .cancel(2))
        precondition(JarvisResearchIntent.parse("자비스, DECHIVE 홍보 플랫폼 조사해줘?") == nil)
        precondition(JarvisResearchIntent.parse("자비스, DECHIVE 홍보 플랫폼 조사하지 마") == nil)
        precondition(JarvisResearchIntent.parse("자비스, 이건 계속 연구해줘") == nil)
        precondition(JarvisResearchIntent.parse("자비스, 안녕") == nil)
        print("PASS: explicit research, report, status, cancel and refusal question guards")
    }
}
