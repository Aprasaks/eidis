import Foundation

@main struct MorningBriefingLive {
    @MainActor static func main() async throws {
        precondition(JarvisBriefingIntent.parse("자비스, 오늘 아침 뉴스 브리핑해줘.") == .show)
        precondition(JarvisBriefingIntent.parse("자비스, 오늘 아침 브리핑해줘") == .show)
        precondition(JarvisBriefingIntent.parse("뉴스 브리핑 닫아") == .hide)
        precondition(JarvisBriefingIntent.parse("뉴스 브리핑하지 마") == nil)
        precondition(JarvisBriefingIntent.parse("뉴스 브리핑이 뭐야?") == nil)
        print("PASS: explicit briefing commands")
        guard CommandLine.arguments.count==2,
              let port=Int(CommandLine.arguments[1]),port != 8765 else {return}
        let client=JarvisBriefingClient(port:port)
        let start=Date()
        let job=try await client.collect { update in
            print("JOB",update.id,update.state)
        }
        precondition(!job.pending && job.state != "failed")
        precondition(job.feeds.count==6)
        precondition(!job.articles.isEmpty)
        precondition(job.articles.allSatisfy {$0.evidence=="publisher_rss_only"})
        precondition(job.result.windowStart != nil && job.result.windowEnd != nil)
        print("LIVE_RESULT",job.state,"feeds",job.feeds.filter{$0.state=="read"}.count,
              "articles",job.articles.count,"elapsed",Date().timeIntervalSince(start))
        for cat in JarvisBriefingJob.categories {
            print(cat,job.articles.filter{$0.category==cat}.count)
        }
        print("SUMMARY",job.summary)
        let again=try await client.collect { _ in }
        precondition(again.id==job.id)
        print("PASS: actual publisher feeds through Swift client, cached replay")
    }
}
