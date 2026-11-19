import AVFoundation
import Foundation
import Speech
import SwiftUI

/// An on-device-only conversation client. The Qwen model cannot execute tools,
/// open files, change project data, or reach paid model APIs via this client.
@MainActor
final class JarvisOverlayConversation: ObservableObject {
    @Published private(set) var status = "자비스 인사 중…"
    @Published private(set) var question = ""
    @Published private(set) var answer = ""
    @Published private(set) var isListening = false
    @Published private(set) var isThinking = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var isActive = false
    // Controlled by SwiftUI FocusState; do not intercept Space while typing.
    var textInputFocused = false

    private let listener = LocalSpeechListener()
    private let macVoice = JarvisVoiceService()
    let dashboard = JarvisOverlayDashboard()
    private let elevenLabs = ElevenLabsVoiceService.shared
    private let session: URLSession
    private var conversation: [[String: String]] = []
    private var generation = UUID()
    private var dialogueTask: Task<Void, Never>?
    private var listeningTask: Task<Void, Never>?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 55
        config.timeoutIntervalForResource = 65
        session = URLSession(configuration: config)
    }

    static var microphoneAlreadyAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized &&
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func afterGreeting() async {
        guard !Task.isCancelled else { return }
        if Self.microphoneAlreadyAuthorized {
            activateListening()
        } else {
            status = "Space를 누르면 마이크 권한을 확인하고 대화를 시작합니다."
        }
    }

    func toggleMicrophone() {
        if isListening {
            completeUtterance()
        } else if !isThinking && !isSpeaking {
            activateListening()
        }
    }

    func activateListening() {
        guard !isListening && !isThinking && !isSpeaking && listeningTask == nil else { return }
        let token = generation
        listeningTask = Task { [weak self] in
            guard let self else { return }
            self.status = "마이크·한국어 음성 인식 확인 중…"
            await self.listener.start()
            guard !Task.isCancelled && self.generation == token else {
                self.listener.cancel()
                self.listeningTask = nil
                return
            }
            self.isListening = self.listener.isListening
            self.isActive = self.listener.isListening
            self.status = self.listener.isListening
                ? "듣는 중 · 말한 뒤 Space를 눌러 질문을 마쳐주세요."
                : self.listener.status
            self.listeningTask = nil
        }
    }

    func completeUtterance() {
        guard isListening && !isThinking else { return }
        isListening = false
        isThinking = true // blocks double-press while recognition finalizes
        let token = generation
        dialogueTask = Task { [weak self] in
            guard let self else { return }
            self.status = "한국어 문장 확인 중…"
            let utterance = await self.listener.finish()
            guard !Task.isCancelled && token == self.generation else { return }
            self.isThinking = false
            guard !utterance.isEmpty else {
                self.status = "인식한 문장이 없습니다. Space를 눌러 다시 말씀해 주세요."
                return
            }
            await self.handleQuestion(utterance, token: token)
        }
    }

    /// Text entry is optional accessibility/fallback input, not a separate chat window.
    func submitTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && !isThinking && !isSpeaking && !isListening else { return }
        let token = generation
        dialogueTask = Task { [weak self] in
            await self?.handleQuestion(trimmed, token: token)
        }
    }

    private func handleQuestion(_ text: String, token: UUID) async {
        guard token == generation && !Task.isCancelled else { return }
        let prompt = String(text.prefix(900))
        question = prompt
        answer = ""
        isThinking = true
        let action = JarvisDashboardIntent.parse(prompt)
        status = action == nil ? "Qwen3.5가 맥에서 답변 중…" : "로컬 작업 기록 확인 중…"
        do {
            let response: String
            switch action {
            case .show: response = await dashboard.show()
            case .hide: response = dashboard.hide()
            case nil: response = try await askQwen(prompt)
            }
            guard !response.isEmpty else { return }
            guard token == generation && !Task.isCancelled else { return }
            isThinking = false
            answer = response
            status = "답변 읽는 중… Esc로 즉시 종료할 수 있습니다."
            isSpeaking = true
            await elevenLabs.speak(response, fallback: macVoice)
            guard token == generation && !Task.isCancelled else { return }
            await elevenLabs.waitForOutputToFinish(fallback: macVoice)
            guard token == generation && !Task.isCancelled else { return }
            isSpeaking = false
            status = "대화 가능 · 다음 질문은 마이크에 말하고 Space로 마쳐주세요."
            if isActive { activateListening() }
        } catch {
            guard token == generation && !Task.isCancelled else { return }
            isThinking = false
            isSpeaking = false
            status = "로컬 Qwen에 연결할 수 없습니다. Ollama 실행 상태를 확인해 주세요."
        }
    }

    private func askQwen(_ prompt: String) async throws -> String {
        let url = URL(string: "http://127.0.0.1:11434/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let system = """
        당신은 개인 Mac AI 비서 자비스입니다. 자연스럽고 짧은 한국어 존댓말로만 답합니다.
        중국어·영어 사고 과정은 출력하지 않습니다. 답변은 보통 1~3문장, 180자 이내로 합니다.
        모르는 사실은 모른다고 말합니다. 실제로 접근하지 않은 화면·일정·파일을 본 척하지 않습니다.
        작업 실행, 삭제, 일정 등록, 검색이 가능한 척하지 마세요. 현재는 대화만 가능합니다.
        음성으로 읽히므로 별표·마크다운·이모지·복잡한 기호 없이 자연스럽게 대답합니다.
        """
        var messages = [["role": "system", "content": system]]
        messages.append(contentsOf: conversation.suffix(8))
        messages.append(["role": "user", "content": prompt])
        let body: [String: Any] = [
            "model": "qwen3.5:9b-q4_K_M",
            "messages": messages,
            "think": false,
            "stream": false,
            "keep_alive": "10m",
            "options": ["num_ctx": 3072, "num_predict": 150, "temperature": 0.4]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 300_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw URLError(.badServerResponse)
        }
        let answer = String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(450))
        guard !answer.isEmpty else { throw URLError(.cannotParseResponse) }
        // Conversation is never written to disk or sent to cloud brain APIs.
        conversation.append(["role": "user", "content": prompt])
        conversation.append(["role": "assistant", "content": answer])
        if conversation.count > 8 { conversation.removeFirst(conversation.count - 8) }
        return answer
    }

    func cancel() {
        generation = UUID()
        dialogueTask?.cancel()
        listeningTask?.cancel()
        dialogueTask = nil
        listeningTask = nil
        listener.cancel()
        isListening = false
        isThinking = false
        isSpeaking = false
        isActive = false
        textInputFocused = false
        elevenLabs.stopSpeakingNow()
        macVoice.stop()
        question = ""
        answer = ""
        conversation.removeAll()
        dashboard.cancel()
        status = "자비스 대화 종료"
        session.invalidateAndCancel()
    }
}
