import Foundation

/// Explicit web research; a question or ordinary conversation never grants
/// background network access. URLs from websites are never action commands.
enum JarvisResearchIntent: Equatable {
    case submit(String)
    case status
    case report(Int)
    case cancel(Int)

    static func parse(_ utterance: String) -> Self? {
        let spoken = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(자비스|jarvis)[,，.!！?\s]*"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = spoken.replacingOccurrences(of: " ", with: "")
        let clean = compact.trimmingCharacters(in: CharacterSet(charactersIn: ".!！"))
        if ["조사현황알려줘", "조사현황", "조사목록보여줘", "리서치현황알려줘",
            "웹조사결과알려줘", "최근조사목록보여줘"].contains(clean) { return .status }
        if !compact.contains("?"), !compact.contains("？") {
            if clean.range(of: #"^(조사|리서치)[1-9][0-9]{0,5}번(중단해|취소해|멈춰|중단해줘)$"#,
                           options: .regularExpression) != nil,
               let matched = clean.range(of: #"[1-9][0-9]{0,5}"#, options: .regularExpression),
               let id = Int(clean[matched]) { return .cancel(id) }
            if clean.range(of: #"^(조사보고서|조사결과|리서치보고서)[1-9][0-9]{0,5}번(보여줘|알려줘|읽어줘)$"#,
                           options: .regularExpression) != nil,
               let matched = clean.range(of: #"[1-9][0-9]{0,5}"#, options: .regularExpression),
               let id = Int(clean[matched]) { return .report(id) }
        }
        // No "계속 연구해줘" because that is an opt-in Thinking Core workflow.
        if compact.contains("?") || compact.contains("？") ||
           ["하지마", "하지말", "검색하지", "조사하지", "아니야", "취소"].contains(where: { compact.contains($0) }) {
            return nil
        }
        let suffixes = ["인터넷에서조사해줘", "웹에서조사해줘", "검색해서조사해줘",
                        "출처찾아서조사해줘", "인터넷으로조사해줘",
                        "웹조사해줘", "자료조사해줘", "조사해줘", "조사해봐",
                        "인터넷에서찾아봐", "웹에서찾아봐"]
        for suffix in suffixes where compact.hasSuffix(suffix) {
            let count = spoken.count - suffix.count
            guard count > 0 else { return nil }
            // Extract the subject by removing the exact suffix words including spaces.
            // A normalized suffix can differ in length from the spoken text.
            let words = spoken.split(separator: " ")
            for cut in 1...min(6,words.count) {
                let candidate = words.dropLast(cut).joined(separator: " ")
                let remainder = words.suffix(cut).joined().replacingOccurrences(of: " ", with: "")
                if remainder == suffix, candidate.count >= 3, candidate.count <= 160 {
                    return .submit(candidate.trimmingCharacters(in: .punctuationCharacters))
                }
            }
            // A Korean suffix may share a token with the subject, e.g. "DECHIVE 조사해줘".
            if compact.count > suffix.count {
                let core = String(compact.dropLast(suffix.count))
                if core.count >= 3 && core.count <= 160 { return .submit(core) }
            }
        }
        return nil
    }
}

struct JarvisResearchSource: Decodable, Identifiable {
    let rank: Int
    let title: String
    let url: String
    let domain: String
    let searchExcerpt: String
    let state: String
    let claimedPublishedAt: String
    let checkedAt: String
    let reason: String
    var id: Int { rank }
    var stateLabel: String {
        switch state {
        case "retrieved": return "원문 수집"
        case "indexed_only": return "검색 결과만"
        case "unavailable": return "접근 실패"
        case "blocked": return "안전 차단"
        default: return "검색 발견"
        }
    }
}

struct JarvisResearchBrief: Decodable {
    let id: Int
    let query: String
    let state: String
    let progress: String
    let summary: String
}
struct JarvisResearchStatus: Decodable {
    let counts: [String: Int]
    let items: [JarvisResearchBrief]
    let latestSources: [JarvisResearchSource]
}

private struct JarvisResearchJob: Decodable {
    let id: Int
    let query: String
    let state: String
    let progress: String
    let summary: String
    let report: String
    let sources: [JarvisResearchSource]
}
private struct JarvisResearchSubmit: Decodable { let job: JarvisResearchJob }
private struct JarvisResearchCancel: Decodable { let cancelled: Bool }

@MainActor
final class JarvisResearchClient {
    private let session: URLSession
    private let port: Int

    init(port: Int = 8765) {
        precondition((1...65535).contains(port))
        self.port = port
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        session = URLSession(configuration: config)
    }

    private func request<T: Decodable>(_ path: String,
                                        payload: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/research" + path),
              url.host == "127.0.0.1", url.port == port else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let payload {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 192_000 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func snapshot() async throws -> JarvisResearchStatus {
        try await request("")
    }

    func handle(_ intent: JarvisResearchIntent) async -> String {
        do {
            switch intent {
            case .submit(let raw):
                let response: JarvisResearchSubmit = try await request(
                    "/submit", payload: ["query": raw])
                return "오빠, 외부 웹 조사 \(response.job.id)번을 접수했습니다. " +
                    "실제 검색·원문 확인 결과를 기록하겠습니다. 검색어는 공개 검색 서비스에 전달됩니다."
            case .status:
                let result = try await snapshot()
                if result.items.isEmpty { return "오빠, 아직 접수한 웹 조사가 없습니다." }
                let items = result.items.prefix(4).map {
                    "조사 \($0.id)번 \($0.query.prefix(40)) · \($0.state) \($0.progress)"
                }
                return "오빠, 웹 조사 현황입니다.\n" + items.joined(separator: "\n")
            case .report(let id):
                let result: JarvisResearchJob = try await request("/job?id=\(id)")
                guard ["completed","partial","failed"].contains(result.state) else {
                    return "오빠, 조사 \(id)번은 현재 \(result.state) 상태입니다. \(result.progress)"
                }
                return "오빠, 웹 조사 \(id)번의 실제 출처 보고서입니다.\n" +
                    (result.report.isEmpty ? result.summary : result.report)
            case .cancel(let id):
                let result: JarvisResearchCancel = try await request("/cancel",
                    payload: ["id": id])
                return result.cancelled
                    ? "오빠, 조사 \(id)번을 중단했습니다. 늦게 도착한 자료는 저장하지 않습니다."
                    : "오빠, 해당 조사는 완료되었거나 중단할 수 없습니다."
            }
        } catch {
            return "오빠, 조사 요청을 확인하지 못했습니다. 접수됐다고 주장하지 않겠습니다."
        }
    }

    func cancelSession() { session.invalidateAndCancel() }
}
