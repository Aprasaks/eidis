import Foundation

@main
struct ThinkingCoreSmoke {
    static func main() {
        precondition(JarvisThinkingRoute.mode(for: "자비스, 안녕") == .fast)
        precondition(JarvisThinkingRoute.mode(for: "자비스, 유튜브 열어줘") == .fast)
        precondition(JarvisThinkingRoute.mode(for: "자비스, 우리 그거 아직 못 했지?") == .contextual)
        precondition(JarvisThinkingRoute.mode(for: "자비스, 지난번 취업 준비 기억나?") == .contextual)
        precondition(JarvisThinkingRoute.mode(for: "자비스, 취업과 프로젝트를 어떻게 생각해?") == .deliberate)
        precondition(JarvisThinkingRoute.mode(for: "자비스, 이 문제 해결 전략을 비교해 봐") == .deliberate)
        precondition(JarvisThoughtIntent.parse("자비스, 방금 생각 기록해줘") == .savePrevious)
        precondition(JarvisThoughtIntent.parse("자비스, 이 판단 저장해") == .savePrevious)
        precondition(JarvisThoughtIntent.parse("자비스, 사고 기록 보여줘") == .list)
        if case let .reject(id, _) = JarvisThoughtIntent.parse("자비스, 3번 생각 틀렸어. 기준을 잘못 잡았어") {
            precondition(id == 3)
        } else { preconditionFailure("Expected explicit rejection intent") }
        if case let .userReviewed(id, _) = JarvisThoughtIntent.parse("자비스, 7번 판단 검토했어") {
            precondition(id == 7)
        } else { preconditionFailure("Expected explicit review intent") }
        precondition(JarvisThoughtIntent.parse("자비스, 유튜브 열어줘") == nil)
        print("PASS: small talk and direct commands remain fast")
        print("PASS: context-dependent and deliberative speech classified automatically")
        print("PASS: explicit thought saves are distinguished from generic commands")
    }
}
