import Foundation

@main struct ActionSmoke {
    static func main() {
        precondition(JarvisActionIntent.parse("자비스, 프로젝트 보고서 만들어줘") == .submit("project_report"))
        precondition(JarvisActionIntent.parse("유튜브 현황 보고서 작성해줘") == .submit("youtube_report"))
        precondition(JarvisActionIntent.parse("프로젝트와 유튜브 보고서 만들어줘") == .submit("overview_report"))
        precondition(JarvisActionIntent.parse("업무 보고서 2번 보여줘") == .report(2))
        precondition(JarvisActionIntent.parse("업무 2번 중단해") == .cancel(2))
        precondition(JarvisActionIntent.parse("업무 현황 알려줘") == .status)
        precondition(JarvisActionIntent.parse("유튜브 보고서 만들어줘?") == nil)
        precondition(JarvisActionIntent.parse("유튜브 보고서 만들지 마") == nil)
        precondition(JarvisActionIntent.parse("업무 2번 취소해?") == nil)
        precondition(JarvisActionIntent.parse("프로젝트 파일 삭제해") == nil)
        print("PASS: explicit report workflows, status, result, cancellation, question and mutation guards")
    }
}
