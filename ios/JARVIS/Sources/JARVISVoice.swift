import AVFoundation
import Speech
import SwiftUI

@MainActor
final class JARVISVoice: NSObject, ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var reply = "필요한 순간에 말해 주세요."
    @Published private(set) var status = "대기 중"
    @Published private(set) var isListening = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var lastResultIsFinal = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    let elevenLabs = JARVISMobileElevenLabs()
    private var speechTask: Task<Void, Never>?
    private var elevenLabsPlayer: AVAudioPlayer?
    private var speechRevision = UUID()
    private var audioRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var hasTap = false
    private var isRecognitionFinal = false
    private var recognitionError = false
    private var sessionID = UUID()

    var busy: Bool { isPreparing || isFinalizing }

    func start() async {
        guard !isListening, !busy else { return }
        let id = UUID()
        sessionID = id
        isPreparing = true
        defer {
            if sessionID == id { isPreparing = false }
        }
        transcript = ""
        isRecognitionFinal = false
        recognitionError = false
        lastResultIsFinal = false
        stopSpeaking()
        status = "마이크 및 한국어 음성 인식 권한 확인 중"

        guard let recognizer, recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            status = "이 기기에서 한국어 온디바이스 음성 인식을 사용할 수 없습니다."
            return
        }
        let speechAuth = await withCheckedContinuation {
            (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard id == sessionID else { return }
        guard speechAuth == .authorized else {
            status = "설정에서 EIDIS의 음성 인식을 허용해 주세요."
            return
        }
        let micAuth = await AVAudioApplication.requestRecordPermission()
        guard id == sessionID else { return }
        guard micAuth else {
            status = "설정에서 EIDIS의 마이크를 허용해 주세요."
            return
        }

        do {
            // Playback-mode audio sessions cannot reliably capture microphone
            // input after ElevenLabs/system TTS. Restore recording first.
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                mode: .measurement, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.contextualStrings = JARVISCommand.hints
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                status = "마이크 입력 형식이 올바르지 않습니다."
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasTap = true
            audioRequest = request
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            status = "듣는 중 · 끝나면 완료를 누르세요"
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == id,
                          self.isListening || self.isFinalizing else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal { self.isRecognitionFinal = true }
                    }
                    if let error, !self.isRecognitionFinal {
                        self.recognitionError = true
                        self.status = "인식 오류: \(error.localizedDescription)"
                        self.stopAudio()
                        if self.isListening {
                            self.isListening = false
                            self.audioRequest?.endAudio()
                            self.recognition?.cancel()
                            self.recognition = nil
                            self.audioRequest = nil
                        }
                    }
                }
            }
        } catch {
            stopAudio()
            audioRequest?.endAudio()
            recognition?.cancel()
            recognition = nil
            audioRequest = nil
            status = "마이크 시작 실패: \(error.localizedDescription)"
        }
    }

    /// Completes the explicit user recording. The UI dispatches the resulting
    /// text to the correct real data service before speaking a reply.
    func finish() async -> String? {
        guard isListening, !busy else { return nil }
        let id = sessionID
        isListening = false
        isFinalizing = true
        status = "한국어 전사 확정 중"
        stopAudio()
        audioRequest?.endAudio()
        for _ in 0..<15 {
            if isRecognitionFinal || recognitionError || sessionID != id { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard sessionID == id else { return nil }
        let content = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        lastResultIsFinal = isRecognitionFinal
        let failed = recognitionError
        recognition?.cancel()
        recognition = nil
        audioRequest = nil
        isFinalizing = false
        guard !failed, !content.isEmpty else {
            status = failed ? "음성 인식 실패 · 전달하지 않음" : "인식한 문장이 없습니다."
            return nil
        }
        status = lastResultIsFinal ? "최종 전사 완료 · 기기 내 처리" : "임시 전사 · 최종 확정되지 않음"
        return content
    }

    func cancel() {
        sessionID = UUID()
        stopAudio()
        audioRequest?.endAudio()
        recognition?.cancel()
        recognition = nil
        audioRequest = nil
        isListening = false
        isPreparing = false
        isFinalizing = false
        transcript = ""
        status = "취소됨 · 음성을 전송하지 않았습니다."
    }

    func speak(_ response: String, for recognized: String) {
        guard !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        transcript = recognized
        reply = response
        stopSpeaking()
        // 2026-11-28 사용자 결정: 목소리 설정 없이 유나 하나만 쓴다 (ElevenLabs 사용 안 함).
        speakSystemVoice(response)
    }

    private func speakSystemVoice(_ text: String) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio,
                                                            options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // System TTS can still attempt playback with the active session.
        }
        // DECHIVE는 언제나 "데카이브"로 읽는다. 유나 프리미엄이 설치돼 있으면 맥과 같은 목소리를 쓴다.
        let spoken = text.replacingOccurrences(of: "DECHIVE", with: "데카이브", options: .caseInsensitive)
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.ko-KR.Yuna")
            ?? AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        speechRevision = UUID()
        speechTask?.cancel()
        speechTask = nil
        elevenLabsPlayer?.stop()
        elevenLabsPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func stopAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
    }
}
