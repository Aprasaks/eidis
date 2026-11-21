"""Regression for the actual ASR-words-visible-but-finish-empty bug."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
SPEECH=(ROOT/"macos/Sources/EidisMac/NativeSpeech.swift").read_text()
DECISION=(ROOT/"macos/Sources/EidisMac/LocalSpeechDecision.swift").read_text()
OVERLAY=(ROOT/"macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
UI=(ROOT/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()

class VisibleSpeechRecoveryTests(unittest.TestCase):
    def test_recognizer_error_does_not_erase_a_real_transcript(self):
        self.assertIn("finishConsumed = false",SPEECH)
        self.assertIn("finishConsumed = true  // never resubmit",SPEECH)
        self.assertIn("isListening || (recognitionFailed && !captured.isEmpty)",SPEECH)
        self.assertIn("let recovered = accepted == nil ? LocalSpeechDecision.recoverCapturedText(",SPEECH)
        self.assertIn('let certainty = provisionalRecovery ? "마지막 임시 전사(오류 후 복구)"',SPEECH)
        self.assertIn('guard sessionId == session else { return "" }',SPEECH)
        self.assertIn("recognitionEpoch &+= 1",SPEECH)
        self.assertIn("let waitSteps = captured.isEmpty ? 15 : 8",SPEECH)

    def test_display_fallback_only_uses_current_recognizer_words(self):
        self.assertIn("let lastVisibleTranscript = self.liveTranscript",OVERLAY)
        self.assertIn("let utterance = await self.listener.finish()",OVERLAY)
        self.assertIn("guard !Task.isCancelled && token == self.generation else { return }",OVERLAY)
        self.assertIn("beforeFinishing: lastVisibleTranscript",OVERLAY)
        self.assertIn("afterFinishing: self.listener.transcript",OVERLAY)
        self.assertIn("let questionText = utterance.isEmpty ? (recovered ??",OVERLAY)
        self.assertIn("guard !questionText.isEmpty else",OVERLAY)
        self.assertIn("await self.handleQuestion(questionText, token: token)",OVERLAY)
        self.assertNotIn("String(repeating:",DECISION)
        self.assertNotIn("Qwen",DECISION)

    def test_provisional_evidence_disclosed_in_both_views(self):
        self.assertIn("마지막 임시 전사 사용 · 확정 과정 오류",OVERLAY)
        self.assertIn('accessibilityIdentifier("jarvis-speech-evidence")',UI)
        self.assertIn('accessibilityIdentifier("jarvis-workspace-speech-evidence")',UI)
        self.assertIn("speechCaptureNotice = \"\"",OVERLAY)

if __name__=="__main__":
    unittest.main()
