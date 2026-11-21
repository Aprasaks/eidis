import Foundation

// Opt-in integration smoke: requires the installed local Qwen model, but
// all study topics and evidence go to an isolated temporary HTTP database.
@main
struct StudyLiveSmoke {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2,
              let port = Int(CommandLine.arguments[1]), port != 8765 else {
            fatalError("An isolated non-production loopback port is required.")
        }
        let client = JarvisStudyClient(port:port)
        let runner = JarvisStudyRunner(port:port,interval:0.3)
        runner.setConversationActive(true)
        runner.start()
        defer { runner.stop() }
        let receipt = await client.register(topic:"테스트 광고 전환율",premise:"기존 가설: 모든 광고 노출이 전환으로 연결된다.")
        print(receipt)
        guard receipt.contains("등록했습니다") else { throw URLError(.badServerResponse) }
        try await Task.sleep(for:.seconds(1))
        let paused = await client.report()
        guard paused.contains("대기 1건, 실행 0건"), paused.contains("초안 0건") else {
            print(paused)
            throw URLError(.badServerResponse)
        }
        print("PASS: no inference while conversation is active")
        runner.setConversationActive(false)
        let deadline=Date().addingTimeInterval(80)
        while Date() < deadline {
            if let count = await client.draftCount(), count > 0 {
                print("PASS: actual local model result received and persisted")
                print(await client.read(1))
                return
            }
            try await Task.sleep(for:.seconds(0.5))
        }
        print(await client.report())
        throw URLError(.timedOut)
    }
}
