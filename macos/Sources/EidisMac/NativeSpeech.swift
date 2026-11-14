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

/// Explicit push-to-talk only. No background listening or transcript archive.
@MainActor
final class LocalSpeechListener: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var status = "마이크가 꺼져 있습니다. 버튼을 누를 때만 듣습니다."

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private let engine = AVAudioEngine()
    private var audioRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start() async {
        guard !isListening else { return }
        transcript = ""

        // SwiftPM's unbundled executable has no usage descriptions. Prevent a privacy-related crash.
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil,
              Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else {
            status = "권한 설명이 포함된 JARVIS.app으로 실행해야 합니다."
            return
        }
        guard let recognizer else {
            status = "한국어 음성 인식을 사용할 수 없습니다."
            return
        }
        guard recognizer.isAvailable else {
            status = "한국어 음성 인식 서비스가 현재 사용 불가능합니다."
            return
        }
        // Never silently fall back to remote speech recognition.
        guard recognizer.supportsOnDeviceRecognition else {
            status = "이 Mac에서는 한국어 온디바이스 인식을 지원하지 않습니다. 외부 전송은 하지 않았습니다."
            return
        }

        let speechPermission = await withCheckedContinuation {
            (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { permission in
                continuation.resume(returning: permission)
            }
        }
        guard speechPermission == .authorized else {
            status = "음성 인식 권한이 허용되지 않았습니다. 시스템 설정에서 확인해 주세요."
            return
        }
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneAllowed else {
            status = "마이크 접근 권한이 허용되지 않았습니다. 시스템 설정에서 확인해 주세요."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        do {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                status = "마이크 입력 형식이 올바르지 않습니다."
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioRequest = request
            engine.prepare()
            try engine.start()
            isListening = true
            status = "듣는 중… 끝나면 ‘완료하고 전달’을 누르세요."

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.isListening else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if let error {
                        self.status = "음성 인식 실패: \(error.localizedDescription)"
                        _ = self.stop()
                    }
                }
            }
        } catch {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            audioRequest = nil
            status = "마이크 시작 실패: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func stop() -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if isListening {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        audioRequest = nil
        isListening = false
        if !status.hasPrefix("음성 인식 실패") {
            status = text.isEmpty ? "인식된 문장이 없습니다." : "음성 인식 종료. 확인된 문장만 전달합니다."
        }
        return text
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
            Label("자비스의 귀 · 한국어 음성 명령", systemImage: "mic")
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
                        .disabled(!elevenLabs.keyPresent || elevenLabs.isBusy || elevenLabs.isCheckingConnection || elevenLabs.remaining == 0)
                        Text("이번 앱 실행: 남은 요청 \(elevenLabs.remaining)/5회")
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
                Button(listener.isListening ? "완료하고 명령 전달" : "마이크로 말하기") {
                    if listener.isListening {
                        let phrase = listener.stop()
                        sendCommand(phrase)
                    } else {
                        Task { await listener.start() }
                    }
                }
                .disabled(client.busy || routingBusy)
                Button("취소") {
                    _ = listener.stop()
                }
                .disabled(!listener.isListening)
                Spacer()
                Text(listener.isListening ? "● LISTENING" : "MIC OFF")
                    .font(.caption.monospaced())
                    .foregroundStyle(listener.isListening ? .cyan : .secondary)
            }
            Text(listener.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("프로젝트 이어하기 예: DECHIVE.WIKI 작업 이어서 열어줘 · 작업 탭에서 별도 승인해야 합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            GroupBox("인식한 문장") {
                ScrollView {
                    Text(listener.transcript.isEmpty ? "예: 자비스, 대시보드 띄워" : listener.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(minHeight: 95)
            }
            HStack {
                TextField("마이크가 안 되면 여기서 명령을 입력하세요.", text: $typedCommand)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendTyped() }
                Button("실행") { sendTyped() }
                    .disabled(client.busy || routingBusy ||
                              typedCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            GroupBox("자비스 응답") {
                Text(workspaceRoutingResult.isEmpty ? client.lastResponse : workspaceRoutingResult)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            Text("일반 명령은 로컬 자비스 서버로 전달합니다. 정확한 프로젝트 이름과 '작업 이어서 열어줘'를 포함한 문장은 이 Mac의 작업 탭에 제안을 만들 뿐, 승인 없이 Finder·GitHub를 열지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private func sendTyped() {
        let phrase = typedCommand
        typedCommand = ""
        sendCommand(phrase)
    }
}
