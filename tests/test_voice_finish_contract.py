"""Source contract for guarded on-device microphone finishing; no audio in CI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOICE = (ROOT / "macos/Sources/EidisMac/NativeSpeech.swift").read_text("utf-8")
DECISION = (ROOT / "macos/Sources/EidisMac/LocalSpeechDecision.swift").read_text("utf-8")
CI = (ROOT / ".github/workflows/ci.yml").read_text("utf-8")


class VoiceFinishContractTests(unittest.TestCase):
    def test_on_device_only_and_explicit_permission(self):
        self.assertIn('SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))', VOICE)
        self.assertIn("recognizer.supportsOnDeviceRecognition", VOICE)
        self.assertIn("request.requiresOnDeviceRecognition = true", VOICE)
        self.assertIn("SFSpeechRecognizer.requestAuthorization", VOICE)
        self.assertIn("AVCaptureDevice.requestAccess(for: .audio)", VOICE)
        self.assertIn("guard session == sessionId else { return }", VOICE)
        self.assertIn('"remote_consent": false', VOICE)

    def test_stopping_audio_precedes_recognition_cancellation(self):
        method = VOICE.split("func finish() async -> String {", 1)[1].split(
            "func cancel()", 1)[0]
        self.assertLess(method.index("stopAudio()"), method.index("audioRequest?.endAudio()"))
        self.assertLess(method.index("audioRequest?.endAudio()"),
                        method.index("for step in 0..<15"))
        self.assertLess(method.index("for step in 0..<15"),
                        method.index("recognitionTask?.cancel()"))
        self.assertIn("let captured = transcript.trimmingCharacters(in: .whitespacesAndNewlines)",method)
        self.assertIn("isListening || (recognitionFailed && !captured.isEmpty)",method)
        self.assertIn("finishConsumed = true",method)
        self.assertIn("LocalSpeechDecision.recoverCapturedText(",method)
        self.assertIn("let waitSteps = captured.isEmpty ? 15 : 8",method)
        self.assertIn("finalReceived || recognitionFailed || sessionId != session", method)
        self.assertIn("LocalSpeechDecision.acceptedText(", method)
        self.assertIn("guard let recognized else", method)
        self.assertIn("Task.sleep(nanoseconds: 100_000_000)", method)

    def test_cancel_blocks_send_and_stale_callbacks(self):
        self.assertIn("sessionId = UUID()", VOICE)
        self.assertIn("self.sessionId == session", VOICE)
        self.assertIn('guard sessionId == session else { return "" }', VOICE)
        self.assertIn("listener.cancel()", VOICE)
        self.assertIn("if !phrase.isEmpty { sendCommand(phrase) }", VOICE)
        self.assertIn(".disabled(client.busy || routingBusy || listener.captureBusy)", VOICE)
        self.assertIn("Text(listener.lastCaptureEvidence)", VOICE)
        self.assertIn('lastCaptureEvidence = ""', VOICE)
        self.assertIn("guard !failed else { return nil }", DECISION)
        self.assertIn('isFinal ? "최종 전사" : "마지막 임시 전사"', DECISION)

    def test_native_smoke_without_microphone_in_ci(self):
        self.assertIn("macos/tests/voice/main.swift", CI)
        self.assertIn("macos/Sources/EidisMac/LocalSpeechDecision.swift", CI)


if __name__ == "__main__":
    unittest.main()
