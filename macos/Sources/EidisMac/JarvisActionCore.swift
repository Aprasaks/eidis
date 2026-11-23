import Foundation

enum JarvisActionIntent: Equatable {
    case submit(String)
    case status
    case report(Int)
    case cancel(Int)

    static func parse(_ prompt: String) -> Self? {
        let s = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(자비스|jarvis)[,，.!\s]*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: " ", with: "")
        let clean = s.trimmingCharacters(in: CharacterSet(charactersIn: ".!?！？"))
        if ["업무현황알려줘", "업무현황", "업무목록보여줘", "작업결과알려줘",
            "업무보고서목록보여줘", "뭐하고있어", "지금업무상태알려줘"].contains(clean) { return .status }
        if !s.contains("?"), !s.contains("？"),
           clean.range(of: #"^업무[1-9][0-9]{0,5}번(중단해|취소해|멈춰|중단해줘)$"#, options: .regularExpression) != nil,
           let range = clean.range(of: #"[1-9][0-9]{0,5}"#, options: .regularExpression),
           let id = Int(clean[range]) { return .cancel(id) }
        if clean.range(of: #"^(업무보고서|업무결과|보고서)[1-9][0-9]{0,5}번(보여줘|알려줘|읽어줘|열어줘)$"#, options: .regularExpression) != nil,
           let range = clean.range(of: #"[1-9][0-9]{0,5}"#, options: .regularExpression),
           let id = Int(clean[range]) { return .report(id) }
        // Persistent task requests require affirmative explicit delegation.
        guard !s.contains("?"), !s.contains("？") else { return nil }
        let targets = [
            ("프로젝트", "project_report"), ("프로젝트현황", "project_report"),
            ("유튜브", "youtube_report"), ("유튜브현황", "youtube_report"),
            ("프로젝트와유튜브", "overview_report"),
            ("프로젝트랑유튜브", "overview_report")
        ]
        let suffixes = ["보고서만들어줘", "보고서작성해줘", "보고서만들어봐", "보고서정리해줘", "현황보고서만들어줘", "현황보고서작성해줘"]
        for (target, workflow) in targets where suffixes.contains(where: { clean == target + $0 }) {
            return .submit(workflow)
        }
        return nil
    }
}

struct JarvisActionJob: Decodable {
    let id: Int
    let workflow: String
    let state: String
    let summary: String
    let report: String?
    let requestedAt: String
    let updatedAt: String

    var label: String {
        switch workflow {
        case "project_report": "프로젝트 보고서"
        case "youtube_report": "유튜브 보고서"
        case "overview_report": "통합 업무 보고서"
        default: "알 수 없는 업무"
        }
    }

    var stateLabel: String {
        switch state {
        case "queued": "대기"
        case "running": "실행 중"
        case "completed": "완료"
        case "partial": "부분 완료"
        case "failed": "실패"
        case "cancelled": "중단"
        default: "미확인"
        }
    }
}

private struct ActionStatus: Decodable {
    let counts: [String: Int]
    let items: [JarvisActionJob]
}
private struct ActionSubmit: Decodable { let job: JarvisActionJob }
private struct ActionCancel: Decodable { let cancelled: Bool }

@MainActor
final class JarvisActionClient {
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

    private func call<T: Decodable>(_ path: String, payload: [String: Any]? = nil) async throws -> T {
        let url = URL(string: "http://127.0.0.1:\(port)/api/action" + path)!
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let payload {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 256_000 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func handle(_ intent: JarvisActionIntent) async -> String {
        do {
            switch intent {
            case .submit(let workflow):
                let result: ActionSubmit = try await call("/submit", payload: ["workflow":workflow])
                return "오빠, 업무 \(result.job.id)번 \(result.job.label)을 접수했습니다. 실제 자료 조회 후 결과를 로컬에 보관합니다. 진행 중에도 대화하실 수 있습니다."
            case .status:
                let result: ActionStatus = try await call("")
                if result.items.isEmpty { return "오빠, 아직 접수된 업무가 없습니다." }
                let rows = result.items.prefix(5).map { "업무 \($0.id)번 \($0.label) · \($0.stateLabel)" }
                return "오빠, 최근 업무 현황입니다. " + rows.joined(separator: "\n")
            case .report(let id):
                let result: JarvisActionJob = try await call("/job?id=\(id)")
                guard result.state == "completed" || result.state == "partial" else {
                    return "오빠, 업무 \(id)번은 \(result.stateLabel) 상태입니다. \(result.summary)"
                }
                return "오빠, 업무 \(id)번 \(result.stateLabel) 보고서입니다.\n" + (result.report ?? result.summary)
            case .cancel(let id):
                let result: ActionCancel = try await call("/cancel", payload: ["id":id])
                return result.cancelled ? "오빠, 업무 \(id)번을 중단했습니다. 늦게 도착하는 조회 결과는 저장하지 않습니다." :
                    "오빠, 해당 업무가 이미 종료되었거나 중단 가능한 업무가 아닙니다."
            }
        } catch {
            return "오빠, 업무 요청을 확인하지 못했습니다. 업무 현황에서 실제 접수 여부를 확인해 주세요."
        }
    }

    func notice() async -> String {
        guard let r: ActionStatus = try? await call("") else { return "" }
        let pending = (r.counts["queued"] ?? 0) + (r.counts["running"] ?? 0)
        let done = (r.counts["completed"] ?? 0) + (r.counts["partial"] ?? 0)
        return pending > 0 || done > 0 ? "업무 대기·실행 \(pending)건 · 저장 보고서 \(done)건" : ""
    }

    func cancelSession() { session.invalidateAndCancel() }
}
