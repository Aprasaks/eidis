import Foundation

/// User-directed, local-only structured archive. Never persists arbitrary chat
/// history, passwords, unstated preferences, or unrelated open websites.
struct JarvisVaultItem: Decodable, Identifiable {
    let id: Int
    let title: String
    let content: String
    let category: String
    let project: String
    let tags: [String]
    let sourceType: String
    let sourceUrl: String
    let sourceStatus: String
    let createdAt: String
    let updatedAt: String
    let archived: Bool
    let duplicate: Bool?

    var categoryLabel: String { JarvisKnowledgeVault.labels[category] ?? "메모" }
    var evidenceLabel: String {
        switch sourceStatus {
        case "user_supplied": "직접 저장"
        case "unverified_external": "웹 원문 · 검증 전"
        case "ai_generated": "AI 답변 · 검증 전"
        default: "출처 미확인"
        }
    }
}

private struct JarvisVaultList: Decodable {
    let items: [JarvisVaultItem]
    let total: Int
    let counts: [String: Int]
}
private struct JarvisVaultSaved: Decodable { let item: JarvisVaultItem }
private struct JarvisVaultSingle: Decodable { let item: JarvisVaultItem }
private struct JarvisVaultArchived: Decodable { let archived: Bool }
private struct JarvisVaultRestored: Decodable { let restored: Bool }

@MainActor
final class JarvisKnowledgeVault: ObservableObject {
    nonisolated static let labels: [String: String] = [
        "ideas": "아이디어", "research": "조사·분석", "projects": "프로젝트",
        "references": "참고 자료", "notes": "일반 메모", "tasks": "할 일 메모"
    ]
    static let categoryOrder = ["ideas", "research", "projects", "references", "notes", "tasks"]
    @Published private(set) var isVisible = false
    @Published private(set) var isLoading = false
    @Published private(set) var items: [JarvisVaultItem] = []
    @Published private(set) var selectedItem: JarvisVaultItem?
    @Published private(set) var total = 0
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var searchLabel = "최근 저장한 자료"
    @Published private(set) var errorText: String?

    private let base = URL(string: "http://127.0.0.1:8765")!
    private let session: URLSession
    private var generation = UUID()
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 9
        session = URLSession(configuration: config)
    }

    private func send<T: Decodable>(_ route: String, payload: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: route, relativeTo: base)?.absoluteURL,
              url.host == "127.0.0.1", url.port == 8765 else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let payload {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 800_000 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func show(query: String = "", category: String = "", itemId: Int? = nil) async -> String {
        isVisible = true
        isLoading = true
        items = []
        total = 0
        selectedItem = nil
        errorText = nil
        let label = [Self.labels[category] ?? "", query].filter { !$0.isEmpty }.joined(separator: " · ")
        searchLabel = label.isEmpty ? "최근 저장한 자료" : "저장 자료 검색 · \(label)"
        let token = UUID()
        generation = token
        do {
            var parts = URLComponents()
            parts.queryItems = [URLQueryItem(name: "query", value: String(query.prefix(120))),
                                URLQueryItem(name: "category", value: category),
                                URLQueryItem(name: "limit", value: "40")]
            let path = "api/vault" + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
            let result: JarvisVaultList = try await send(path)
            guard !Task.isCancelled && generation == token else { return "" }
            items = result.items
            total = result.total
            counts = result.counts
            if let itemId {
                if let matched = result.items.first(where: { $0.id == itemId }) { selectedItem = matched }
                else if itemId > 0 {
                    let one: JarvisVaultSingle = try await send("api/vault/item?id=\(itemId)")
                    if !one.item.archived { selectedItem = one.item }
                }
            }
            guard !Task.isCancelled && generation == token else { return "" }
            isLoading = false
            if let itemId, selectedItem != nil { return "저장 번호 \(itemId)번 자료를 보관함에 표시했습니다." }
            if result.total == 0 { return "일치하는 저장 자료가 없습니다. 보관함은 열었습니다." }
            let kind = category.isEmpty ? "자료" : (Self.labels[category] ?? "자료")
            return "주인님, 저장한 \(kind) \(result.total)건을 보관함에 보여드릴게요."
        } catch {
            guard !Task.isCancelled && generation == token else { return "" }
            isLoading = false
            errorText = "로컬 보관함을 열지 못했습니다. 저장소를 확인해 주세요."
            return errorText!
        }
    }

    func save(title: String, content: String, sourceType: String = "user_text", sourceURL: String = "") async -> String {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && text.count <= 8000 else { return "내용이 없거나 저장 가능한 길이를 넘었습니다." }
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        guard !title.isEmpty else { return "자료 제목이 필요합니다." }
        let payload = ["title": title, "content": text,
                       "source_type": sourceType, "source_url": sourceURL]
        do {
            let receipt: JarvisVaultSaved = try await send("api/vault", payload: payload)
            guard !Task.isCancelled else { return "" }
            let item = receipt.item
            // Visible confirmation with actual persisted ID, not a model claim.
            let showResult = await show(itemId: item.id)
            if showResult.isEmpty { return "" }
            return item.duplicate == true
                ? "이미 저장된 자료입니다. 보관함 \(item.id)번을 보여드릴게요."
                : "주인님, \(item.categoryLabel) 분류로 \(item.id)번에 저장했습니다. 보관함에 표시했어요."
        } catch {
            return "자료를 저장하지 못했습니다. 내용이나 로컬 서버 상태를 확인해 주세요."
        }
    }

    func archive(id: Int) async -> String {
        guard id > 0 else { return "정확한 자료 번호를 말씀해 주세요." }
        do {
            let receipt: JarvisVaultArchived = try await send("api/vault/archive", payload: ["id": id])
            let visibleResult = await show()
            if visibleResult.isEmpty { return "" }
            return receipt.archived
                ? "\(id)번 자료를 보관 처리했습니다. 원본은 복원 가능하게 남아 있습니다."
                : "\(id)번 자료를 보관 처리하지 못했습니다. 번호를 확인해 주세요."
        } catch { return "보관 처리를 완료하지 못했습니다." }
    }

    func restore(id: Int) async -> String {
        guard id > 0 else { return "정확한 자료 번호를 말씀해 주세요." }
        do {
            let receipt: JarvisVaultRestored = try await send("api/vault/restore", payload: ["id": id])
            let visibleResult = await show(itemId: id)
            if visibleResult.isEmpty { return "" }
            return receipt.restored ? "\(id)번 자료를 복원했습니다." : "복원할 자료를 찾지 못했습니다."
        } catch { return "자료를 복원하지 못했습니다." }
    }

    func hide() -> String {
        generation = UUID()
        isVisible = false
        isLoading = false
        items = []
        selectedItem = nil
        total = 0
        counts = [:]
        errorText = nil
        return "자료 보관함을 닫았습니다."
    }

    func cancel() {
        _ = hide()
        session.invalidateAndCancel()
    }
}

/// Human phrasing routes only explicit save/search/archive actions.
/// Storage classification remains deterministic server-side, and nothing
/// reaches an external API or web search engine through this parser.
enum JarvisVaultIntent: Equatable {
    case saveText(String)
    case saveCurrent
    case saveContext
    case show(String, String, Int?)
    case hide
    case archive(Int)
    case restore(Int)
    case needsContent

    static func parse(_ utterance: String) -> Self? {
        let raw = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count <= 8000 else { return .needsContent }
        let s = raw.replacingOccurrences(of: #"^(자비스|jarvis)[,，?？.!！\s]*"#, with: "",
                                          options: [.regularExpression, .caseInsensitive])
        let compact = s.lowercased().replacingOccurrences(of: " ", with: "")
        let vaultWord = ["보관함", "저장한", "저장된", "저장해둔", "메모목록", "저장목록", "저장자료",
                         "내자료", "모아둔", "기록해둔"].contains { compact.contains($0) }
        let hide = ["닫아", "꺼줘", "숨겨", "치워", "접어", "없애"].contains { compact.contains($0) }
        if compact.contains("보관함") && hide { return .hide }

        if let id = numberedItem(compact), ["복원", "되돌려"].contains(where: { compact.contains($0) }) {
            return .restore(id)
        }
        if let id = numberedItem(compact), (["보관처리", "보관해", "보관함에서지워", "자료삭제", "메모삭제"].contains(where: { compact.contains($0) }) ||
            ((compact.contains("자료") || compact.contains("메모")) && ["지워", "삭제"].contains(where: { compact.contains($0) }))) {
            return .archive(id)
        }

        let saveSuffixes = ["저장해줘", "저장해 줘", "저장해 둬", "저장해둬", "저장해", "보관해줘",
                            "보관해 줘", "보관해", "기록해줘", "기록해 줘", "기억해줘", "기억해 줘", "기억해"]
        if let suffix = saveSuffixes.first(where: { s.hasSuffix($0) }) {
            var content = String(s.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if ["이페이지", "지금페이지", "이웹페이지", "현재페이지", "이사이트", "지금보는페이지", "이기사"].contains(where: { compact.contains($0) }) {
                return .saveCurrent
            }
            if ["이거", "그거", "이내용", "방금내용", "방금답변", "방금한말", "아까그거"].contains(where: {
                content.replacingOccurrences(of: " ", with: "").contains($0)
            }) && content.count < 32 { return .saveContext }
            content = content.replacingOccurrences(of: #"^(메모|아이디어|자료|내용|기억|기록)[을를]?[\s:：,-]+"#,with:"",options:.regularExpression)
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if ["내용", "자료", "메모", "기록", "이것"].contains(content) { return .needsContent }
            return content.isEmpty ? .needsContent : .saveText(content)
        }
        let display = ["보여", "찾아", "검색", "열어", "목록", "뭐였", "뭘저장", "무엇을저장", "확인"].contains { compact.contains($0) }
        if vaultWord && display {
            let id = numberedItem(compact)
            let category: String
            if compact.contains("아이디어") { category = "ideas" }
            else if compact.contains("조사") || compact.contains("연구") || compact.contains("분석") { category = "research" }
            else if compact.contains("프로젝트") || compact.contains("작업기록") { category = "projects" }
            else if compact.contains("할일") || compact.contains("체크리스트") { category = "tasks" }
            else if compact.contains("참고자료") || compact.contains("링크") { category = "references" }
            else if compact.contains("일반메모") { category = "notes" }
            else { category = "" }
            let search = searchTerm(s, category: category)
            return .show(search, category, id)
        }

        return nil
    }

    private static func numberedItem(_ s: String) -> Int? {
        let pattern = #"(?:^|[^0-9])([1-9][0-9]{0,5})번"#
        guard let match = s.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(s[match])
        guard let digits = matched.range(of: #"[1-9][0-9]{0,5}"#, options: .regularExpression) else { return nil }
        return Int(matched[digits])
    }

    private static func searchTerm(_ original: String, category: String) -> String {
        var s = original
        // Strip command words, never arbitrary payload substrings from saved notes.
        for regex in [#"[0-9]+번"#, #"저장(해|된|한|해둔|했던)?"#, #"(보관함|내 자료|자료|메모|목록|모아둔|기록해둔)"#,
                      #"(찾아|검색|보여|열어|확인|알려|꺼내)(줘|주세요|줄래|봐)?"#,
                      #"(지난번|전에|아까|예전에|어제|나한테|내가|것|중에서|관련된)"#,
                      #"(아이디어|조사|연구|분석|프로젝트|할 일|참고|링크)"#] {
            s = s.replacingOccurrences(of: regex, with: " ", options: .regularExpression)
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // e.g. "블로그" is a useful search term; empty means show category/list.
        let words = s.split(whereSeparator: { $0.isWhitespace }).filter { $0.count > 1 }
        return String(words.joined(separator: " ").prefix(100))
    }
}
