import Foundation

@main struct OllamaStreamLiveSmoke {
    @MainActor static func main() async throws {
        let started=Date()
        let session=URLSession(configuration:.ephemeral)
        var request=URLRequest(url:URL(string:"http://127.0.0.1:11434/api/chat")!)
        request.httpMethod="POST"
        request.timeoutInterval=75
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:[
            "model":"qwen3.5:9b-q4_K_M",
            "messages":[["role":"system","content":"당신은 자비스입니다. 오빠라고 부르며 한국어 한 문장으로 답하세요."],
                        ["role":"user","content":"인사해줘"]],
            "think":false,"stream":true,"keep_alive":"10m",
            "options":["num_ctx":2048,"num_predict":100,"temperature":0.1]
        ])
        var updates=0
        var first:Double?
        let text=try await JarvisOllamaTextStream.receive(request:request,session:session) { part in
            updates+=1
            if first==nil {first=Date().timeIntervalSince(started)}
            precondition(part.count<=900)
        }
        let elapsed=Date().timeIntervalSince(started)
        print("STREAM_TEST first_visible_s:",String(format:"%.3f",first ?? -1),
              "complete_s:",String(format:"%.3f",elapsed),"updates:",updates,
              "text:",text)
        precondition(!text.isEmpty && updates>=1)
        precondition(first != nil && first!<=elapsed)
        print("PASS: actual local Qwen NDJSON streaming first text before completed answer")
    }
}
