import Foundation

/// Ollama NDJSON streaming for safe conversational replies only.
/// No tool execution, file writes, or public network connections. Display
/// incoming text as a draft, only commit to history after done:true arrives.
@MainActor
enum JarvisOllamaTextStream {
    private struct Chunk: Decodable {
        struct Message: Decodable {
            let content: String?
            let toolCalls: [EmptyCall]?
            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        struct EmptyCall: Decodable {}
        let message: Message?
        let done: Bool?
        let error: String?
    }

    static func receive(
        request: URLRequest,
        session: URLSession,
        maxReplyChars: Int = 450,
        onPartial: @MainActor (String) -> Void
    ) async throws -> String {
        let (bytes,response)=try await session.bytes(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoder=JSONDecoder()
        var content=""
        var finished=false
        var lineCount=0
        let started=Date()
        var firstVisibleLogged=false
        var lastUIPush=Date.distantPast
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.utf8.count<=32_000 else {throw URLError(.dataLengthExceedsMaximum)}
            lineCount+=1
            guard lineCount<=1500 else {throw URLError(.dataLengthExceedsMaximum)}
            let chunk=try decoder.decode(Chunk.self,from:Data(line.utf8))
            guard chunk.error==nil, chunk.message?.toolCalls?.isEmpty != false else {
                throw URLError(.cannotParseResponse)
            }
            if let text=chunk.message?.content,!text.isEmpty {
                content+=text
                guard content.count<=1600 else {throw URLError(.dataLengthExceedsMaximum)}
                if !firstVisibleLogged {
                    firstVisibleLogged=true
                    NSLog("DECHIVE conversational stream first_text_ms=%.1f",
                          Date().timeIntervalSince(started)*1000)
                }
                if Date().timeIntervalSince(lastUIPush)>=0.07 {
                    onPartial(String(content.prefix(max(450, min(maxReplyChars, 1200)))))
                    lastUIPush=Date()
                }
            }
            if chunk.done==true {finished=true;break}
        }
        try Task.checkCancellation()
        guard finished else {throw URLError(.cannotParseResponse)}
        let final=content.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !final.isEmpty else {throw URLError(.cannotParseResponse)}
        onPartial(String(final.prefix(max(450, min(maxReplyChars, 1200)))))
        NSLog("DECHIVE conversational stream completed_ms=%.1f",
              Date().timeIntervalSince(started)*1000)
        return String(final.prefix(max(1, min(maxReplyChars, 1200))))
    }
}
