import AppKit
import AVFoundation
import Speech
import SwiftUI

/// A UI event that carries a verified reply from the local JARVIS server.
struct JarvisCommandReply: Codable {
    let spoken: String
    let text: String
    let mode: String
    let action: String
    let executed: Bool
    let design_prompt: String?
    let conversation_id: String?
    let brain_source: String?
}

struct JarvisVisualEvent: Identifiable {
    let id = UUID()
    let reply: JarvisCommandReply
}

@MainActor
final class JarvisBridge: ObservableObject {
    @Published var event: JarvisVisualEvent?
}

/// Route the existing microphone tap to whichever short recognition segment is
/// active. The lock prevents a swap from racing with the audio callback.
private final class JarvisSpeechAudioRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func replace(with next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        let old = request
        request = next
        old?.endAudio()
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()
    }
}

/// Explicit push-to-talk only. No background listening or transcript archive.
/// Ending audio is not the same as cancelling speech recognition. We allow
/// a bounded finalization period before forwarding any recognized words.
@MainActor
final class LocalSpeechListener: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isStarting = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var transcript = ""
    @Published private(set) var status = "마이크가 꺼져 있습니다. 버튼을 누를 때만 듣습니다."
    @Published private(set) var lastCaptureEvidence = ""
    @Published private(set) var activeMicrophone = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private let engine = AVAudioEngine()
    private var audioRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioRelay = JarvisSpeechAudioRelay()
    private var assembled = JarvisSpeechTranscriptAssembler()
    private var recognitionEpoch: UInt = 0
    private var tapInstalled = false
    private var finalReceived = false
    private var recognitionFailed = false
    private var finishConsumed = true
    private var sessionId = UUID()

    var captureBusy: Bool { isStarting || isFinalizing }

    func start() async {
        guard !isListening, !isStarting, !isFinalizing else { return }
        let session = UUID()
        sessionId = session
        isStarting = true
        defer { if sessionId == session { isStarting = false } }
        transcript = ""
        assembled.reset()
        recognitionEpoch &+= 1
        audioRelay.replace(with: nil)
        lastCaptureEvidence = ""
        activeMicrophone = ""
        finalReceived = false
        recognitionFailed = false
        finishConsumed = false
        status = "한국어 음성 인식과 마이크 권한을 확인합니다."

        // SwiftPM's unbundled executable has no usage descriptions.
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil,
              Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else {
            status = "권한 설명이 포함된 DECHIVE 앱으로 실행해야 합니다."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            status = "한국어 음성 인식 서비스를 이용할 수 없습니다."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            status = "한국어 온디바이스 인식을 지원하지 않습니다. 외부 인식 서비스를 사용하지 않았습니다."
            return
        }
        let speechPermission = await withCheckedContinuation {
            (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { permission in
                continuation.resume(returning: permission)
            }
        }
        guard session == sessionId else { return }
        guard speechPermission == .authorized else {
            status = "음성 인식 권한이 허용되지 않았습니다. 시스템 설정에서 확인해 주세요."
            return
        }
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard session == sessionId else { return }
        guard microphoneAllowed else {
            status = "마이크 접근 권한이 허용되지 않았습니다. 시스템 설정에서 확인해 주세요."
            return
        }

        do {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                status = "마이크 입력 형식이 올바르지 않습니다."
                return
            }
            let relay = audioRelay
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                relay.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            let name = AVCaptureDevice.default(for: .audio)?.localizedName ?? "이름 확인 불가"
            activeMicrophone = "Mac 입력: \(String(name.prefix(70))) · \(Int(format.sampleRate))Hz"
            isListening = true
            status = "듣는 중… 인식된 문장은 쉬었다 이어가도 유지됩니다."
            beginRecognitionSegment(session: session)
        } catch {
            stopAudio()
            audioRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionTask = nil
            audioRequest = nil
            isListening = false
            status = "마이크 시작 실패: \(error.localizedDescription)"
        }
    }

    /// A final result can arrive before the person finishes speaking. Keep
    /// listening on the *same microphone turn* while starting a new segment.
    private func beginRecognitionSegment(session: UUID) {
        guard sessionId == session, isListening || isFinalizing,
              let recognizer, recognizer.isAvailable else { return }
        recognitionEpoch &+= 1
        let epoch = recognitionEpoch
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        // Natural Korean questions are closer to dictation than command words.
        // Vocabulary hints favor brand/domain terms but do not rewrite output.
        request.taskHint = .dictation
        request.contextualStrings = JarvisSpeechVocabulary.phrases
        audioRequest = request
        finalReceived = false
        audioRelay.replace(with: request)
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.sessionId == session,
                      self.recognitionEpoch == epoch,
                      self.isListening || self.isFinalizing else { return }
                if let result {
                    self.transcript = self.assembled.receive(
                        result.bestTranscription.formattedString,
                        isFinal: result.isFinal)
                    if result.isFinal {
                        self.finalReceived = true
                        if self.isListening {
                            // Reject callbacks from the old recognition task.
                            self.recognitionTask?.cancel()
                            self.recognitionTask = nil
                            self.beginRecognitionSegment(session: session)
                            return
                        }
                    }
                }
                if let error, !self.finalReceived {
                    self.recognitionFailed = true
                    self.status = "음성 인식 실패: \(error.localizedDescription). 명령은 보내지 않았습니다."
                    self.stopAudio()
                    if self.isListening {
                        self.isListening = false
                        self.audioRelay.replace(with: nil)
                        self.recognitionTask?.cancel()
                        self.recognitionTask = nil
                        self.audioRequest = nil
                    }
                }
            }
        }
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    /// End the actual microphone capture and use only words produced by the
    /// on-device recognizer. If ending the stream errors after a visible
    /// partial result, keep that text but explicitly mark it provisional.
    func finish() async -> String {
        let captured = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finishConsumed, !isFinalizing, !isStarting,
              isListening || (recognitionFailed && !captured.isEmpty) else { return "" }
        finishConsumed = true  // never resubmit the same transcript twice
        let session = sessionId
        let alreadyStopped = !isListening
        isFinalizing = true
        isListening = false
        status = "녹음을 마쳤습니다. 인식 문장을 확정하고 있습니다."
        stopAudio()
        audioRequest?.endAudio()
        // Give the recognizer a short opportunity to correct a visible
        // partial result. Without text, preserve the old 1.5s maximum.
        let waitSteps = captured.isEmpty ? 15 : 8
        for step in 0..<15 {
            if finalReceived || recognitionFailed || sessionId != session ||
               alreadyStopped { break }
            if step >= waitSteps { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard sessionId == session else { return "" }
        let accepted = LocalSpeechDecision.acceptedText(
            transcript, failed: recognitionFailed)
        let recovered = accepted == nil ? LocalSpeechDecision.recoverCapturedText(
            beforeFinishing: captured, afterFinishing: transcript) : nil
        let recognized = accepted ?? recovered
        let provisionalRecovery = accepted == nil && recovered != nil
        let final = finalReceived && !recognitionFailed && !provisionalRecovery
        let failed = recognitionFailed
        recognitionEpoch &+= 1
        recognitionTask?.cancel()
        recognitionTask = nil
        audioRelay.replace(with: nil)
        audioRequest = nil
        isFinalizing = false
        guard let recognized else {
            status = failed
                ? "음성 인식이 종료 중 실패했고 복구할 문장도 없습니다. 전송하지 않았습니다."
                : "인식된 문장이 없습니다. 서버에 아무 명령도 보내지 않았습니다."
            return ""
        }
        let certainty = provisionalRecovery ? "마지막 임시 전사(오류 후 복구)" :
            LocalSpeechDecision.recognitionLabel(isFinal: final)
        lastCaptureEvidence = "\(certainty) · 한국어 온디바이스 인식 · \(Date().formatted(date: .omitted, time: .standard)) · 서버 전송은 별도 단계"
        status = "\(certainty) 문장 확보: \(recognized). 명령 전달을 시도합니다."
        return recognized
    }

    func cancel() {
        // Invalidate any late recognition or permissions callbacks.
        sessionId = UUID()
        recognitionEpoch &+= 1
        stopAudio()
        audioRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        audioRelay.replace(with: nil)
        audioRequest = nil
        isStarting = false
        isListening = false
        isFinalizing = false
        recognitionFailed = false
        finalReceived = false
        finishConsumed = true
        transcript = ""
        assembled.reset()
        lastCaptureEvidence = ""
        status = "음성 입력을 취소했습니다. 아무 명령도 보내지 않았습니다."
    }
}

@MainActor
final class LocalCommandClient: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var lastResponse = "아직 실행한 명령이 없습니다."
    private var conversationID: String?

    func submit(_ text: String, bridge: JarvisBridge, voice: JarvisVoiceService, elevenLabs: ElevenLabsVoiceService) async {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        lastResponse = "로컬 자비스에 명령을 전달하고 있습니다…"
        do {
            let url = URL(string: "http://127.0.0.1:8765/api/chat")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            // A public GitHub check can involve several independent GET requests.
            // Longer timeout is only for explicit GitHub status requests; this does
            // not grant broader permissions or start a background task.
            let compact = phrase.lowercased().replacingOccurrences(of: " ", with: "")
            let githubInspection = (compact.contains("github") || compact.contains("깃허브")
                || compact.contains("깃헙"))
                && (compact.contains("확인") || compact.contains("조회")
                    || compact.contains("상태") || compact.contains("점검"))
            request.timeoutInterval = githubInspection ? 36 : 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var commandBody: [String: Any] = [
                "text": phrase,
                "remote_consent": false
            ]
            if let conversationID { commandBody["conversation_id"] = conversationID }
            request.httpBody = try JSONSerialization.data(withJSONObject: commandBody)
            let (payload, response) = try await URLSession.shared.data(for: request)
            guard let status = response as? HTTPURLResponse, status.statusCode == 200 else {
                lastResponse = "로컬 명령 처리에 실패했습니다. 서버와 입력값을 확인해 주세요."
                return
            }
            let answer = try JSONDecoder().decode(JarvisCommandReply.self, from: payload)
            conversationID = answer.conversation_id
            bridge.event = JarvisVisualEvent(reply: answer)
            lastResponse = answer.text
            await elevenLabs.speak(answer.spoken, fallback: voice)
        } catch {
            lastResponse = "로컬 서버 연결 실패: \(error.localizedDescription)"
        }
    }
}

struct NativeSpeechPanel: View {
    @ObservedObject var bridge: JarvisBridge
    @ObservedObject var voice: JarvisVoiceService
    @ObservedObject var elevenLabs: ElevenLabsVoiceService
    @ObservedObject var projectWork: ApprovedWorkModel
    let onWorkspaceRequest: (JarvisWorkspaceCommand) -> Void
    @State private var elevenAPIKeyDraft = ""
    @StateObject private var listener = LocalSpeechListener()
    @StateObject private var client = LocalCommandClient()
    @State private var typedCommand = ""
    @State private var routingBusy = false
    @State private var workspaceRoutingResult = ""

    /// Recognized project-opening phrases stay local and produce only a
    /// proposal. Ordinary questions retain the existing local chat behavior.
    private func sendCommand(_ phrase: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !routingBusy, !client.busy else { return }
        workspaceRoutingResult = ""
        if JarvisWorkspaceCommandParser.isOpenRequest(trimmed) {
            routingBusy = true
            Task {
                defer { routingBusy = false }
                // Only the existing loopback project list is read here.
                // The parser never guesses a project from incomplete names.
                if projectWork.projects.isEmpty { await projectWork.refresh() }
                switch JarvisWorkspaceCommandParser.parse(trimmed, projects: projectWork.projects) {
                case .ordinary:
                    await client.submit(trimmed, bridge: bridge, voice: voice, elevenLabs: elevenLabs)
                case .matched(let request):
                    workspaceRoutingResult = "\(request.projectName) 작업 공간 열기 제안을 만들었습니다. 작업 탭에서 대상을 확인하고 직접 승인해 주세요. 아직 열지 않았습니다."
                    onWorkspaceRequest(request)
                case .missingProject:
                    workspaceRoutingResult = "입력한 문장과 정확히 일치하는 등록 프로젝트를 찾지 못했습니다. 프로젝트 전체 이름을 적어 주세요. 실행하지 않았습니다."
                case .ambiguous:
                    workspaceRoutingResult = "여러 프로젝트명이 일치합니다. 프로젝트 전체 이름을 정확히 입력해 주세요. 실행하지 않았습니다."
                case .unsupported:
                    workspaceRoutingResult = "열기와 함께 변경·삭제·배포를 요청하는 문장은 처리하지 않습니다. 작업 공간 열기만 별도로 요청해 주세요."
                }
            }
        } else {
            Task { await client.submit(trimmed, bridge: bridge, voice: voice, elevenLabs: elevenLabs) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            Label("DECHIVE의 귀 · 한국어 음성 명령", systemImage: "mic")
                .font(.headline)
            Text("사용자가 누르는 동안만 마이크를 엽니다. 지원되는 Mac에서는 한국어 온디바이스 음성 인식만 사용합니다. 항상 듣기·화면 분석·외부 AI 연결은 아직 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            GroupBox("Mac 기본 목소리 · ElevenLabs와 별개") {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 12) {
                        if voice.availableVoices.isEmpty {
                            Text("이 Mac에 설치된 한국어 목소리가 없습니다.")
                                .font(.caption)
                        } else {
                            Picker("목소리", selection: $voice.voiceID) {
                                ForEach(voice.availableVoices, id: \.identifier) { option in
                                    Text(option.name).tag(option.identifier)
                                }
                            }
                            .frame(maxWidth: 390)
                        }
                        Button("Mac 음성 미리 듣기") { voice.preview() }
                            .disabled(voice.availableVoices.isEmpty)
                        Button("초기화") { voice.resetToDefault() }
                            .disabled(voice.availableVoices.isEmpty)
                    }
                    HStack(spacing: 10) {
                        Text("말하는 속도").font(.caption).frame(width: 74, alignment: .leading)
                        Slider(value: $voice.speed, in: 0.38...0.58, step: 0.01)
                        Text(String(format: "%.2f", voice.speed))
                            .font(.caption.monospacedDigit()).frame(width: 36)
                    }
                    HStack(spacing: 10) {
                        Text("음높이").font(.caption).frame(width: 74, alignment: .leading)
                        Slider(value: $voice.pitch, in: 0.75...1.25, step: 0.05)
                        Text(String(format: "%.2f", voice.pitch))
                            .font(.caption.monospacedDigit()).frame(width: 36)
                    }
                    Text("설치는 필요 없고 macOS에 있는 음성을 사용합니다. 선택한 설정은 다음 실행에도 유지됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            GroupBox("ElevenLabs · 선택한 목소리") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Voice ID").font(.caption).frame(width: 70, alignment: .leading)
                        TextField("ElevenLabs Voice ID", text: $elevenLabs.voiceID)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                            .accessibilityIdentifier("elevenlabs-voice-id")
                    }
                    HStack {
                        Text("모델").font(.caption).frame(width: 70, alignment: .leading)
                        Picker("모델", selection: $elevenLabs.modelID) {
                            Text("Flash v2.5 · 빠르고 저렴").tag("eleven_flash_v2_5")
                            Text("Multilingual v2 · 높은 음질").tag("eleven_multilingual_v2")
                        }
                        .labelsHidden()
                    }
                    HStack(spacing: 9) {
                        SecureField("ElevenLabs API 키 (Mac 키체인에 저장)", text: $elevenAPIKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("elevenlabs-api-key")
                        Button("키 저장") {
                            if elevenLabs.saveKey(elevenAPIKeyDraft) {
                                elevenAPIKeyDraft = ""
                            }
                        }
                        .disabled(elevenAPIKeyDraft.isEmpty)
                        Button("키 삭제") { elevenLabs.removeKey() }
                            .disabled(!elevenLabs.keyPresent)
                    }
                    Toggle("이후 자비스 답변을 ElevenLabs로 음성 생성 (텍스트 외부 전송·크레딧 사용)",
                           isOn: $elevenLabs.enabled)
                        .disabled(!elevenLabs.keyPresent)
                        .font(.caption)
                    HStack(spacing: 12) {
                        Button("연결 확인 · 음성 생성 없음") {
                            Task { await elevenLabs.checkVoiceConnection() }
                        }
                        .disabled(!elevenLabs.keyPresent || elevenLabs.isCheckingConnection || elevenLabs.isBusy)
                        Button("ElevenLabs 미리 듣기 · 크레딧 사용") {
                            Task { await elevenLabs.preview(fallback: voice) }
                        }
                        .disabled(!elevenLabs.keyPresent || elevenLabs.isBusy || elevenLabs.isCheckingConnection)
                        Text("이번 앱 실행: \(elevenLabs.attempts)회 요청 · 한도는 ElevenLabs 계정 설정에 따름")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(elevenLabs.keyPresent ? "API 키: Mac 키체인에 저장됨" : "API 키: 미등록")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("ElevenLabs 실제 상태: " + elevenLabs.status)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("elevenlabs-status")
                    Text("위쪽 Mac 목소리 미리 듣기는 항상 로컬 음성입니다. ElevenLabs 연결 확인은 음성 생성 요청이 아니며, 실제 음질 확인은 크레딧 사용 미리 듣기를 눌러야 합니다. 600자를 넘는 답변이나 오류는 Mac 목소리로 대체합니다. 음성으로 만들 답변 텍스트는 ElevenLabs로 전송됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            HStack {
                Button(listener.isFinalizing ? "인식 확정 중…" :
                       listener.isStarting ? "마이크 권한 확인 중…" :
                       listener.isListening ? "완료하고 명령 전달" : "마이크로 말하기") {
                    if listener.isListening {
                        Task {
                            let phrase = await listener.finish()
                            if !phrase.isEmpty { sendCommand(phrase) }
                        }
                    } else {
                        Task { await listener.start() }
                    }
                }
                .disabled(client.busy || routingBusy || listener.captureBusy)
                Button("취소") {
                    listener.cancel()
                }
                .disabled(!(listener.isListening || listener.captureBusy))
                Spacer()
                Text(listener.isListening ? "● LISTENING" :
                     listener.captureBusy ? "PROCESSING" : "MIC OFF")
                    .font(.caption.monospaced())
                    .foregroundStyle(listener.isListening ? .cyan : .secondary)
            }
            Text(listener.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if !listener.lastCaptureEvidence.isEmpty {
                Text(listener.lastCaptureEvidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("마이크로 실제 명령 점검: 'DECHIVE, 다음 할 일 뭐야?'라고 말하세요. 음성 인식 문장과 아래 로컬 서버 응답을 각각 확인합니다. 음성이 실제로 들렸는지는 직접 확인해야 합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("프로젝트 이어하기 예: DECHIVE.WIKI 작업 이어서 열어줘 · 아래 메뉴에서 다른 등록 프로젝트도 선택할 수 있어요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            GroupBox("인식한 문장") {
                ScrollView {
                    Text(listener.transcript.isEmpty ? "예: DECHIVE, 대시보드 띄워" : listener.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(minHeight: 95)
            }
            HStack {
                Button("DECHIVE 다음 할 일") {
                    sendCommand("자비스, 다음 할 일 뭐야?")
                }
                .disabled(routingBusy || client.busy)
                .help("DECHIVE.WIKI의 저장된 작업을 로컬 서버에서 읽고 답합니다. GitHub 조회나 코드 실행은 하지 않습니다.")
                Menu("등록 프로젝트 선택") {
                    ForEach(projectWork.projects) { project in
                        Button(project.name) {
                            typedCommand = "\(project.name) 작업 이어서 열어줘"
                        }
                    }
                }
                .disabled(projectWork.projects.isEmpty || routingBusy || client.busy)
                Button("목록 갱신") {
                    Task { await projectWork.refresh() }
                }
                .disabled(projectWork.busy || routingBusy || client.busy)
                Spacer()
                Text("선택하면 입력만 됩니다. 실행과 열기 승인은 별개입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("마이크가 안 되면 여기서 명령을 입력하세요.", text: $typedCommand)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendTyped() }
                Button("실행") { sendTyped() }
                    .disabled(client.busy || routingBusy ||
                              typedCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            GroupBox("DECHIVE 응답") {
                Text(workspaceRoutingResult.isEmpty ? client.lastResponse : workspaceRoutingResult)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            Text("일반 명령은 로컬 DECHIVE 서버로 전달합니다. 정확한 프로젝트 이름과 '작업 이어서 열어줘'를 포함한 문장은 이 Mac의 작업 탭에 제안을 만들 뿐, 승인 없이 Finder·GitHub를 열지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .task {
            if projectWork.projects.isEmpty {
                await projectWork.refresh()
            }
        }
    }

    private func sendTyped() {
        let phrase = typedCommand
        typedCommand = ""
        sendCommand(phrase)
    }
}
