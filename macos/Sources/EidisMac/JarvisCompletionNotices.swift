import Foundation

/// CLI 작업(Claude·Codex·Gemini)이 끝나면 이디스가 한두 문장으로 알려준다 (기획서 P1).
///
/// - 결과는 로컬 Qwen이 요약한다. 요약에 실패하면 고정 문장으로 알린다.
/// - 대화 중(듣기·생각·말하기)에는 끼어들지 않고 대기열에 두었다가 대화가 끊기면 말한다.
/// - 아이폰에도 잠금화면 알림을 보낸다 (밖에 있을 때를 위해).
/// - 밤 근무(00:00~08:00)에는 소리 내어 말하지 않고 대화창 기록과 아이폰 알림만 남긴다.
@MainActor
final class JarvisCompletionNotices {
    static let shared = JarvisCompletionNotices()

    struct Notice {
        let agent: String
        let text: String
        let at: Date
    }

    /// 대화 쪽이 등록한다. 지금 전달할 수 있으면 전달하고 true, 바쁘면 false (대기열에 남김).
    var deliver: ((Notice, _ speak: Bool) -> Bool)?
    private(set) var queue: [Notice] = []
    private var drainTask: Task<Void, Never>?

    static func isQuietHours(_ date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour < 8
    }

    /// 작업 하나가 끝났을 때 부른다. detail은 작업 출력의 마지막 부분(사람이 읽을 수 있는 줄).
    func report(agent: String, ok: Bool, cancelled: Bool, detail: String) {
        Task {
            let en = JarvisConversationLanguage.english
            let fallback = cancelled ? (en ? "\(agent) task was stopped." : "\(agent) 작업을 중단했어요.")
                : ok ? (en ? "\(agent) task is done." : "\(agent) 작업이 끝났어요.")
                : (en ? "\(agent) task ended with an error. Check the work panel." : "\(agent) 작업이 오류로 끝났어요. 작업 패널에서 확인해 주세요.")
            var text = fallback
            if !cancelled, let summary = await Self.summarize(agent: agent, ok: ok, detail: detail) {
                text = summary
            }
            let notice = Notice(agent: agent, text: text, at: Date())
            queue.append(notice)
            if queue.count > 10 { queue.removeFirst(queue.count - 10) }
            JarvisPushNotifier.shared.send(title: "EIDIS · \(agent)", body: text, page: "core")
            startDraining()
        }
    }

    /// 요약 없이 바로 알리는 한 줄 (P4 먼저 말 걸기: 일정 10분 전, 1시간 안에 비).
    func announce(agent: String, text: String, pushTitle: String, page: String = "core") {
        queue.append(Notice(agent: agent, text: text, at: Date()))
        if queue.count > 10 { queue.removeFirst(queue.count - 10) }
        JarvisPushNotifier.shared.send(title: pushTitle, body: text, page: page)
        startDraining()
    }

    private func startDraining() {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            while let self, !self.queue.isEmpty, !Task.isCancelled {
                if let deliver = self.deliver, deliver(self.queue[0], !Self.isQuietHours()) {
                    self.queue.removeFirst()
                    // 연달아 끝난 작업은 한 번에 몰아 말하지 않고 조금씩 띄운다.
                    try? await Task.sleep(for: .seconds(4))
                } else {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            self?.drainTask = nil
        }
    }

    /// 로컬 Qwen으로 1~2문장 요약. 외부 API는 부르지 않는다.
    private static func summarize(agent: String, ok: Bool, detail: String) async -> String? {
        let tail = String(detail.suffix(3_500)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return nil }
        let system = JarvisConversationLanguage.english ? """
        You are EIDIS, DECHIVE's personal assistant. Below is the last output of a \(agent) task.
        Tell DECHIVE the result in one or two natural, concise English sentences.
        Start with what finished, like '\(agent) is done.', then give only the key result or the cause of an error.
        Do not invent anything that is not in the output, and do not copy file paths, code or raw log lines. Never use Korean.
        Task status: \(ok ? "finished normally" : "ended with an error")
        """ : """
        당신은 DECHIVE의 개인 비서 이디스입니다. 아래는 \(agent) 작업의 마지막 출력입니다.
        DECHIVE에게 결과를 한두 문장의 자연스러운 한국어 해요체로 알려 주세요.
        첫 문장은 '\(agent) 작업 끝났어요.'처럼 무엇이 끝났는지로 시작하고, 핵심 결과나 오류 원인만 말하세요.
        출력에 없는 내용은 지어내지 말고, 파일 경로·코드·로그 원문은 옮기지 마세요. 'DECHIVE 님'처럼 '님'을 붙이지 마세요.
        작업 상태: \(ok ? "정상 완료" : "오류로 종료")
        """
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": JarvisLocalModelConfiguration.selectedModel,
            "messages": [["role": "system", "content": system], ["role": "user", "content": tail]],
            "stream": false, "think": false, "keep_alive": JarvisLocalModelConfiguration.keepAlive,
            "options": ["num_ctx": JarvisLocalModelConfiguration.contextLength, "num_predict": 160, "temperature": 0.2]
        ] as [String: Any])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { return nil }
        return JarvisPhoneChat.tidy(String(content.prefix(400)))
    }
}
