import AVFoundation
import SwiftUI

/// Native Korean TTS. Nothing is uploaded; preferences are held by macOS UserDefaults.
@MainActor
final class JarvisVoiceService: ObservableObject {
    private static let voiceKey = "jarvis.voice.selectedIdentifier"
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

    func speak(_ text: String) {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID)
            ?? AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = Float(speed)
        utterance.pitchMultiplier = Float(pitch)
        synthesizer.speak(utterance)
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
