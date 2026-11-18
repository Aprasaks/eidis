import Foundation

/// Pure speech-finalization decision; no microphone, network or UI access.
enum LocalSpeechDecision {
    static func acceptedText(_ transcript: String, failed: Bool) -> String? {
        guard !failed else { return nil }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func recognitionLabel(isFinal: Bool) -> String {
        isFinal ? "최종 전사" : "마지막 임시 전사"
    }
}
