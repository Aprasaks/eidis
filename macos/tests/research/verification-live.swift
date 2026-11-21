import Foundation

@main
struct VerificationLiveSmoke {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2,
              let port=Int(CommandLine.arguments[1]), port != 8765 else {
            fatalError("Use only an isolated test server port.")
        }
        let client=JarvisVerificationClient(port:port)
        let runner=JarvisVerificationRunner(port:port,interval:0.35)
        runner.setConversationActive(true)
        runner.start()
        defer { runner.stop() }
        let receipt=await client.handle(.submit(1))
        print("RECEIPT:",receipt)
        guard receipt.contains("접수했습니다") else {throw URLError(.badServerResponse)}
        try await Task.sleep(for:.seconds(1))
        var status=try await client.snapshot()
        guard status.latestResult?.state=="queued" else {
            throw URLError(.badServerResponse)
        }
        print("PASS: verified no Qwen task while conversation panel is shown")
        runner.setConversationActive(false)
        let deadline=Date().addingTimeInterval(90)
        while Date()<deadline {
            status=try await client.snapshot()
            if let result=status.latestResult,
               ["draft","insufficient","failed"].contains(result.state) {
                print("VERIFICATION_FINAL:",result.state,"SUMMARY:",result.summary)
                print("REPORT:",result.report.prefix(1800))
                guard result.state=="draft" else {
                    throw URLError(.badServerResponse)
                }
                guard result.report.contains("원문 그대로의 인용") else {
                    throw URLError(.badServerResponse)
                }
                print("PASS: actual local Qwen returned source-bound claim and saved result")
                return
            }
            try await Task.sleep(for:.seconds(0.5))
        }
        throw URLError(.timedOut)
    }
}
