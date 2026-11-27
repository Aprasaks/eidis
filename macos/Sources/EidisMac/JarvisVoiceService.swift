import AVFoundation
import SwiftUI

/// Native Korean TTS. Nothing is uploaded; preferences are held by macOS UserDefaults.
@MainActor
final class JarvisVoiceService: ObservableObject {
    // v2: 2026-11-28 한국어 전환 때 기본 목소리를 유나 프리미엄으로 새로 잡는다 (예전 v1 선택은 무시).
    private static let voiceKey = "jarvis.voice.selectedIdentifier.v2"
    private static let speedKey = "jarvis.voice.speechRate"
    private static let pitchKey = "jarvis.voice.pitchMultiplier"

    let availableVoices: [AVSpeechSynthesisVoice]
    private let synthesizer = AVSpeechSynthesizer()
    private let preferences: UserDefaults

    @Published var voiceID: String {
        didSet {
            if availableVoices.contains(where: { $0.identifier == voiceID }) {
                preferences.set(voiceID, forKey: Self.voiceKey)
            }
        }
    }
    @Published var speed: Double {
        didSet { preferences.set(speed, forKey: Self.speedKey) }
    }
    @Published var pitch: Double {
        didSet { preferences.set(pitch, forKey: Self.pitchKey) }
    }

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "ko-KR" }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        availableVoices = voices

        let saved = preferences.string(forKey: Self.voiceKey)
        // Readily available on the user's Mac; fall back to a real local voice.
        let preferred = [
            saved,
            "com.apple.voice.premium.ko-KR.Yuna",
            "com.apple.voice.enhanced.ko-KR.Yuna",
            "com.apple.eloquence.ko-KR.Reed",
            "com.apple.voice.compact.ko-KR.Yuna"
        ].compactMap { $0 }.first(where: { id in
            voices.contains(where: { $0.identifier == id })
        })
        voiceID = preferred ?? voices.first?.identifier ?? ""
        let storedSpeed = preferences.object(forKey: Self.speedKey) as? Double
        let storedPitch = preferences.object(forKey: Self.pitchKey) as? Double
        speed = min(max(storedSpeed ?? 0.45, 0.38), 0.58)
        pitch = min(max(storedPitch ?? 0.88, 0.75), 1.25)
    }

    func speak(_ text: String, rateOverride: Double? = nil) {
        // 영어 모드: Kokoro "Heart" (무료·로컬). Kokoro는 한국어를 못 하므로 한국어 모드는 Mac 음성(유나 프리미엄).
        if JarvisKokoroVoice.shared.isPrimary && JarvisConversationLanguage.english {
            let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return }
            synthesizer.stopSpeaking(at: .immediate)
            Task { @MainActor in
                if await !JarvisKokoroVoice.shared.speak(raw) { self.speakNative(text, rateOverride: rateOverride) }
            }
            return
        }
        speakNative(text, rateOverride: rateOverride)
    }

    /// Mac 내장 음성 (대체용). 한글이 없으면 영어 음성으로 읽는다.
    private func speakNative(_ text: String, rateOverride: Double?) {
        if text.range(of: "[가-힣]", options: .regularExpression) == nil {
            // DECHIVE는 항상 "데카이브"로 (Mac 음성은 철자를 하나씩 읽으므로 발음대로 적어 준다)
            let english = text.replacingOccurrences(of: "dechive", with: "Deh-kive", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty else { return }
            synthesizer.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: english)
            utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.en-US.Samantha")
                ?? AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
            return
        }
        let phrase = KoreanSpeechText.normalize(JarvisConversationLanguage.spoken(text))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID)
            ?? AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = Float(min(max(rateOverride ?? speed, 0.38), 0.58))
        utterance.pitchMultiplier = Float(pitch)
        synthesizer.speak(utterance)
    }

    var isSpeaking: Bool { synthesizer.isSpeaking || JarvisKokoroVoice.shared.isPlaying }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        JarvisKokoroVoice.shared.stop()
    }

    func preview() {
        speak("네, 듣고 있습니다. 요청하신 내용을 확인하겠습니다.")
    }

    func resetToDefault() {
        let preferredID = "com.apple.eloquence.ko-KR.Reed"
        if availableVoices.contains(where: { $0.identifier == preferredID }) {
            voiceID = preferredID
        } else if let first = availableVoices.first {
            voiceID = first.identifier
        }
        speed = 0.45
        pitch = 0.88
    }
}
