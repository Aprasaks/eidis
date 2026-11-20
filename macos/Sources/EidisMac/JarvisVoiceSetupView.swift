import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Private, manual enrollment for the owner's voice. Nothing records automatically.
/// The audio and generated previews remain in ~/Library/Application Support/DECHIVE-JARVIS.
@MainActor
final class JarvisVoiceCloneSetup: NSObject, ObservableObject {
    static let recordingScript = "안녕하세요. 저는 자비스의 새로운 목소리를 만들고 있습니다. 천천히 또렷하게 말하며, 중요한 작업을 정확하게 확인하겠습니다."
    static let previewPhrase = "네, 자비스입니다. 무엇을 도와드릴까요?"
    @Published var referenceText = recordingScript
    @Published private(set) var referenceURL: URL?
    @Published private(set) var generatedURL: URL?
    @Published private(set) var originalGeneratedURL: URL?
    @Published private(set) var isRecording = false
    @Published private(set) var isGenerating = false
    @Published private(set) var status = "아래 문장을 자연스럽게 읽고 녹음해 주세요."

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var startedAt: Date?
    private let sampleDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DECHIVE-JARVIS/voice-clone", isDirectory: true)
    private let backendDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/JARVIS-VOICE-LOCAL", isDirectory: true)

    override init() {
        super.init()
        if let path = UserDefaults.standard.string(forKey: "jarvis.voiceClone.referenceURL"),
           FileManager.default.fileExists(atPath: path) {
            referenceURL = URL(fileURLWithPath: path)
            referenceText = UserDefaults.standard.string(forKey: "jarvis.voiceClone.referenceText") ?? Self.recordingScript
            status = "기존 녹음이 있습니다. 정확한 녹음 문장을 확인해 주세요."
        }
    }

    func startRecording() async {
        guard !isRecording && !isGenerating else { return }
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard allowed else {
            status = "마이크 권한이 필요합니다. macOS 설정 → 개인정보 보호 및 보안 → 마이크에서 DECHIVE를 허용해 주세요."
            return
        }
        do {
            try FileManager.default.createDirectory(at: sampleDirectory, withIntermediateDirectories: true)
            let path = sampleDirectory.appendingPathComponent("owner-reference-\(Int(Date().timeIntervalSince1970)).wav")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 24000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let audio = try AVAudioRecorder(url: path, settings: settings)
            guard audio.record() else { status = "녹음을 시작하지 못했습니다."; return }
            recorder = audio
            startedAt = Date()
            referenceURL = path
            generatedURL = nil
            originalGeneratedURL = nil
            isRecording = true
            status = "녹음 중… 안내 문장을 천천히 읽고 '녹음 끝내기'를 눌러 주세요."
        } catch {
            status = "녹음 실패: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        isRecording = false
        guard let referenceURL else { return }
        let duration = Date().timeIntervalSince(startedAt ?? Date())
        guard duration >= 3 && duration <= 35 else {
            status = "녹음 길이 \(Int(duration))초. 5~20초 정도로 다시 녹음해 주세요."
            self.referenceURL = nil
            return
        }
        UserDefaults.standard.set(referenceURL.path, forKey: "jarvis.voiceClone.referenceURL")
        UserDefaults.standard.set(Self.recordingScript, forKey: "jarvis.voiceClone.referenceText")
        referenceText = Self.recordingScript
        status = "\(Int(duration))초 녹음 완료. 재생해 보고 음성 복제 시험을 눌러 주세요."
    }

    func chooseExistingRecording() {
        guard !isRecording && !isGenerating else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.wav, .mp3, .mpeg4Audio, .aiff]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.message = "본인 목소리가 담긴 5~20초 음성 파일을 선택해 주세요."
        guard picker.runModal() == .OK, let url = picker.url else { return }
        referenceURL = url
        generatedURL = nil
        originalGeneratedURL = nil
        referenceText = ""
        UserDefaults.standard.set(url.path, forKey: "jarvis.voiceClone.referenceURL")
        UserDefaults.standard.removeObject(forKey: "jarvis.voiceClone.referenceText")
        status = "파일 선택 완료. 녹음에서 실제로 말한 문장을 아래 입력란에 정확히 적어 주세요."
    }

    func playReference() { if let referenceURL { play(referenceURL) } }
    func playOriginal() { if let originalGeneratedURL { play(originalGeneratedURL) } }
    func playLowerVoice() { if let generatedURL { play(generatedURL) } }
    private func play(_ file: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: file)
            player?.prepareToPlay()
            guard player?.play() == true else { status = "음성 재생을 시작하지 못했습니다."; return }
        } catch { status = "재생 실패: \(error.localizedDescription)" }
    }

    func generatePreview() async {
        guard !isRecording && !isGenerating, let referenceURL else { return }
        let transcript = referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            status = "참조 음성에서 실제 말한 문장을 먼저 입력해 주세요."
            return
        }
        guard FileManager.default.isExecutableFile(atPath: backendDirectory.appendingPathComponent(".venv/bin/python").path),
              FileManager.default.fileExists(atPath: backendDirectory.appendingPathComponent("generate_clone.py").path) else {
            status = "로컬 Qwen3-TTS 환경을 찾지 못했습니다."
            return
        }
        isGenerating = true
        generatedURL = nil
        originalGeneratedURL = nil
        status = "로컬 모델이 목소리를 만드는 중입니다. 녹음은 Mac 밖으로 전송하지 않습니다."
        UserDefaults.standard.set(transcript, forKey: "jarvis.voiceClone.referenceText")
        let backend = backendDirectory
        let samplePhrase = Self.previewPhrase
        let folder = sampleDirectory
        let selected = referenceURL.path
        let output = folder.appendingPathComponent("jarvis-lower-preview-\(Int(Date().timeIntervalSince1970)).wav")
        let log = folder.appendingPathComponent("generation-status.log")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let exitCode = try await Task.detached(priority: .userInitiated) { () throws -> Int32 in
                let task = Process()
                task.executableURL = backend.appendingPathComponent(".venv/bin/python")
                task.arguments = [backend.appendingPathComponent("generate_clone.py").path,
                                  "--reference", selected, "--reference-text", transcript,
                                  "--text", samplePhrase,
                                  "--output", output.path, "--pitch", "0.95"]
                task.currentDirectoryURL = backend
                // Do not expose microphone recordings to a network API.
                var environment = ProcessInfo.processInfo.environment
                for key in ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ELEVENLABS_API_KEY", "HF_TOKEN"] { environment.removeValue(forKey: key) }
                environment["HF_HUB_OFFLINE"] = "1" // model must be downloaded before use
                environment["PYTHONDONTWRITEBYTECODE"] = "1"
                task.environment = environment
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let handle = try FileHandle(forWritingTo: log)
                defer { try? handle.close() }
                task.standardOutput = handle
                task.standardError = handle
                try task.run()
                task.waitUntilExit()
                return task.terminationStatus
            }.value
            guard exitCode == 0 && FileManager.default.fileExists(atPath: output.path) else {
                status = "생성하지 못했습니다. 로그: \(log.lastPathComponent). 기존 DECHIVE 음성은 그대로 유지됩니다."
                isGenerating = false
                return
            }
            generatedURL = output
            originalGeneratedURL = output.deletingLastPathComponent()
                .appendingPathComponent(output.deletingPathExtension().lastPathComponent + "_original.wav")
            status = "로컬 목소리 생성 완료! 원본 생성 음성과 낮은 톤을 비교해 주세요. 기존 DECHIVE 답변 음성은 아직 변경하지 않았습니다."
        } catch {
            status = "생성 실행 실패: \(error.localizedDescription)"
        }
        isGenerating = false
    }
}

struct JarvisVoiceSetupView: View {
    @StateObject private var voice = JarvisVoiceCloneSetup()

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("DECHIVE · 내 목소리 만들기")
                .font(.system(size: 23, weight: .semibold))
            Text("네 목소리를 참고해 조금 더 낮고 차분한 DECHIVE 목소리를 로컬에서 생성해 봅니다.")
                .foregroundStyle(.secondary)
            Text("읽을 문장")
                .font(.headline)
            Text(JarvisVoiceCloneSetup.recordingScript)
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button(voice.isRecording ? "녹음 끝내기" : "내 목소리 녹음") {
                    if voice.isRecording { voice.stopRecording() }
                    else { Task { await voice.startRecording() } }
                }
                .disabled(voice.isGenerating)
                Button("기존 녹음 선택") { voice.chooseExistingRecording() }
                    .disabled(voice.isRecording || voice.isGenerating)
                Button("녹음 듣기") { voice.playReference() }
                    .disabled(voice.referenceURL == nil || voice.isRecording)
            }
            Text("참조 음성에서 실제로 말한 문장 (녹음했다면 자동 입력됨)")
                .font(.headline)
            TextEditor(text: $voice.referenceText)
                .frame(height: 72)
                .border(.gray.opacity(0.25))
                .disabled(voice.isRecording || voice.isGenerating)
            HStack(spacing: 12) {
                Button("내 목소리로 DECHIVE 시험 음성 만들기") {
                    Task { await voice.generatePreview() }
                }
                .disabled(voice.referenceURL == nil || voice.isRecording || voice.isGenerating)
                Button("생성 음성 듣기") { voice.playOriginal() }
                    .disabled(voice.originalGeneratedURL == nil)
                Button("낮은 톤 듣기") { voice.playLowerVoice() }
                    .disabled(voice.generatedURL == nil)
            }
            Text(voice.status)
                .font(.system(size: 12))
                .foregroundStyle(voice.isGenerating ? .orange : .secondary)
            Text("음성 파일은 Mac에만 저장됩니다. 사용자가 직접 녹음 버튼을 누르지 않으면 마이크는 실행되지 않습니다. 생성 결과를 듣고 승인하기 전에는 기존 DECHIVE의 음성이 바뀌지 않습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 650, minHeight: 500)
    }
}
