import Foundation

/// 기획서 P7 M3 · 폰 대화 학습 (승인형).
///
/// 낮에 폰 이디스와 나눈 대화(~/.jarvis-lab/phone-chat/날짜.jsonl)에서, 밤(03:00~07:00)에 로컬 Qwen이
/// "오래 기억할 만한 선호·원칙·목표"만 후보로 뽑는다. 후보는 기존 승인형 학습 저장소(/api/learning)의
/// "pending"으로 들어가고, DECHIVE가 폰 승인 탭에서 승인한 것만 기억이 된다. 모델 자체는 학습시키지 않는다.
@MainActor
final class JarvisPhoneLearning {
    static let shared = JarvisPhoneLearning()
    static let requestKind = "learningRequest"

    private let memory = JarvisLearningMemory()
    private var loop: Task<Void, Never>?
    private static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".jarvis-lab/phone-chat", isDirectory: true)
    private static let stateFile = folder.appendingPathComponent("learned-lines.json")

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runIfDue()
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
            }
        }
    }

    private func runIfDue() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let hour = calendar.component(.hour, from: Date())
        // 밤 지식 작업(00~01시)·캐러셀(01:30~02:30)이 끝난 뒤, DECHIVE가 일어나기 전
        guard (3..<7).contains(hour), !JarvisAgentTerminalBay.shared.nightShiftRunning else { return }
        let added = await extractNewLines()
        if added > 0 {
            JarvisPushNotifier.shared.send(title: "🧠 기억할까요? \(added)개",
                                           body: "어제 폰 대화에서 기억 후보를 찾았어요. 승인 탭에서 고르면 그것만 기억해요.",
                                           page: "approval")
        }
    }

    /// 아직 안 읽은 대화 줄만 읽어서 후보를 만든다. 만든 후보 수를 돌려준다.
    func extractNewLines() async -> Int {
        var state = (try? Data(contentsOf: Self.stateFile))
            .flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        let files = ((try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var utterances: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n")
            let done = state[file.lastPathComponent] ?? 0
            guard lines.count > done else { continue }
            for line in lines[done...] {
                guard let data = line.data(using: .utf8),
                      let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let user = row["user"] as? String else { continue }
                utterances.append(user)
            }
            state[file.lastPathComponent] = lines.count
        }
        guard !utterances.isEmpty else { return 0 }
        await memory.refresh()
        let before = memory.pendingCount
        // 승인 전에는 답변에 쓰지 않는 "후보" 저장만 켠다 (기존 학습 저장소의 규칙 그대로).
        if !memory.enabled { _ = await memory.respond(to: .enable(true)) }
        for utterance in utterances.suffix(60) where JarvisLearningMemory.shouldExtract(utterance, casualChat: true) {
            await memory.observe(utterance, casualChat: true)
        }
        await memory.refresh()
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: Self.stateFile, options: .atomic) }
        return max(0, memory.pendingCount - before)
    }

    /// 폰 승인 탭: kind "learningRequest" {action: list|approve|reject, id} → "learningReply"
    func handle(_ request: [String: Any], requestID: String) async -> [String: Any] {
        let action = request["action"] as? String ?? "list"
        var message: String?
        if let id = request["id"] as? Int, action == "approve" || action == "reject" {
            message = await memory.respond(to: action == "approve" ? .approve(id) : .reject(id))
        }
        await memory.refresh()
        let pending: [[String: Any]] = memory.pending.prefix(30).map {
            ["id": $0.id, "category": $0.category, "content": $0.content, "source": String($0.sourceExcerpt.prefix(200))]
        }
        var reply: [String: Any] = ["kind": "learningReply", "requestID": requestID,
                                    "pending": pending, "approvedCount": memory.approvedCount]
        if let message { reply["message"] = message }
        return reply
    }
}

/// 기획서 P6 A1 · SNS 긴급 정지. 켜져 있으면 인스타·Threads 자동 게시를 모두 멈춘다 (제작·승인은 그대로).
enum JarvisSNSPause {
    static let requestKind = "snsPauseRequest"
    private static let key = "eidis.sns.autopost.paused"

    static var paused: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// 폰: kind "snsPauseRequest" {set: Bool?} → "snsPauseReply" {paused}
    @MainActor
    static func handle(_ request: [String: Any], requestID: String) -> [String: Any] {
        if let value = request["set"] as? Bool, value != paused {
            paused = value
            JarvisPushNotifier.shared.send(title: value ? "⏸ SNS 자동 게시 멈춤" : "▶️ SNS 자동 게시 다시 켬",
                                           body: value ? "인스타·Threads 자동 게시를 멈췄어요. 제작과 승인은 그대로예요."
                                                       : "승인된 글은 다음 게시 시간에 올라가요.", page: "approval")
        }
        return ["kind": "snsPauseReply", "requestID": requestID, "paused": paused]
    }
}
