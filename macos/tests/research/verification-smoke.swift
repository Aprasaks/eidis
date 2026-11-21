import Foundation

@main
struct VerificationSmoke {
    @MainActor static func main() {
        precondition(JarvisVerificationIntent.parse("자비스, 조사 1번 검증해줘") == .submit(1))
        precondition(JarvisVerificationIntent.parse("자비스, 조사 27번 교차 검증해줘") == .submit(27))
        precondition(JarvisVerificationIntent.parse("자비스, 검증 현황 알려줘") == .status)
        precondition(JarvisVerificationIntent.parse("자비스, 검증 보고서 1번 보여줘") == .report(1))
        precondition(JarvisVerificationIntent.parse("자비스, 검증 3번 중단해") == .cancel(3))
        precondition(JarvisVerificationIntent.parse("자비스, 조사 1번 검증해줘?") == nil)
        precondition(JarvisVerificationIntent.parse("자비스, 조사 1번 검증하지 마") == nil)
        precondition(JarvisVerificationIntent.parse("자비스, 프로젝트 조사해줘") == nil)
        let a=UUID(),b=UUID()
        precondition(JarvisLocalModelGate.acquire(a))
        precondition(!JarvisLocalModelGate.acquire(b))
        JarvisLocalModelGate.release(a)
        precondition(JarvisLocalModelGate.acquire(b))
        JarvisLocalModelGate.release(b)
        print("PASS: explicit verification requests, guardrails and shared background model gate")
    }
}
