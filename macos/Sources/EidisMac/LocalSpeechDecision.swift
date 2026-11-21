import Foundation

/// Pure speech-finalization decision; no microphone, network or UI access.
enum LocalSpeechDecision {
    static func acceptedText(_ transcript: String, failed: Bool) -> String? {
        guard !failed else { return nil }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Recover ONLY a word sequence actually emitted by SFSpeechRecognizer
    /// during this turn. A service error while ending audio may prevent an
    /// isFinal callback; that must not erase text the user already saw.
    /// Recovered text remains provisional and must never be called final.
    static func recoverCapturedText(beforeFinishing: String, afterFinishing: String) -> String? {
        let after = afterFinishing.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = beforeFinishing.trimmingCharacters(in: .whitespacesAndNewlines)
        if !after.isEmpty { return after }
        return before.isEmpty ? nil : before
    }

    static func recognitionLabel(isFinal: Bool) -> String {
        isFinal ? "최종 전사" : "마지막 임시 전사"
    }
}

/// A single user turn may contain multiple speech-recognition segments. Preserve
/// finalized segments when Apple's recognizer ends one after a natural pause.
/// Partial results for the *current* segment remain replaceable, because Apple
/// continuously corrects words until it marks that segment final.
struct JarvisSpeechTranscriptAssembler {
    private(set) var confirmedSegments: [String] = []
    private(set) var currentPartial = ""

    var combinedText: String {
        (confirmedSegments + (currentPartial.isEmpty ? [] : [currentPartial]))
            .joined(separator: " ")
    }

    mutating func receive(_ raw: String, isFinal: Bool) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            if !text.isEmpty { confirmedSegments.append(text) }
            currentPartial = ""
        } else {
            currentPartial = text
        }
        return combinedText
    }

    mutating func reset() {
        confirmedSegments.removeAll()
        currentPartial = ""
    }
}
