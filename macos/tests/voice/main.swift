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

var ongoing = JarvisSpeechTranscriptAssembler()
precondition(ongoing.receive("자비스 오늘 아침", isFinal: false) == "자비스 오늘 아침")
precondition(ongoing.receive("자비스 오늘 아침에는", isFinal: false) == "자비스 오늘 아침에는")
precondition(ongoing.receive("자비스 오늘 아침에는", isFinal: true) == "자비스 오늘 아침에는")
precondition(ongoing.receive("잠깐 쉬었고", isFinal: false) == "자비스 오늘 아침에는 잠깐 쉬었고")
precondition(ongoing.receive("잠깐 쉬었고 다시 말했어", isFinal: true) ==
             "자비스 오늘 아침에는 잠깐 쉬었고 다시 말했어")
ongoing.reset()
precondition(ongoing.receive("새 질문", isFinal: true) == "새 질문")
print("PASS finalized speech segments survive natural pauses within a turn")

// Voice hardware is not opened here. Real microphone, macOS TCC and TTS
// confirmation requires direct user interaction within JARVIS.app.
