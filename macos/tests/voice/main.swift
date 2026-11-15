import Foundation

precondition(LocalSpeechDecision.acceptedText(" 자비스, 다음 할 일 뭐야? \n", failed: false)
             == "자비스, 다음 할 일 뭐야?")
precondition(LocalSpeechDecision.acceptedText("  \n\t ", failed: false) == nil)
precondition(LocalSpeechDecision.acceptedText("", failed: false) == nil)
precondition(LocalSpeechDecision.acceptedText("실패 직전 임시 인식", failed: true) == nil)
precondition(LocalSpeechDecision.recognitionLabel(isFinal: true) == "최종 전사")
precondition(LocalSpeechDecision.recognitionLabel(isFinal: false) == "마지막 임시 전사")
print("PASS Korean recognized words forwarded only when nonempty and recognition did not fail")
print("PASS partial speech evidence never labelled as finalized")

// Voice hardware is not opened here. Real microphone, macOS TCC and TTS
// confirmation requires direct user interaction within JARVIS.app.
