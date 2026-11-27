"""Non-intrusive local ASR vocabulary and visible input-device diagnostics."""
from pathlib import Path
import unittest  # 2026-11-27: 영어 대화·Kokoro Heart 음성으로 갱신 (사용자 요청)

ROOT=Path(__file__).resolve().parents[1]
SPEECH=(ROOT/"macos/Sources/EidisMac/NativeSpeech.swift").read_text()
VOCAB=(ROOT/"macos/Sources/EidisMac/JarvisSpeechVocabulary.swift").read_text()
OVERLAY=(ROOT/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
CHAT=(ROOT/"macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()

class OnDeviceSpeechHintsTests(unittest.TestCase):
    def test_korean_speech_stays_local_and_adds_short_domain_terms(self):
        self.assertIn('SFSpeechRecognizer(locale: JarvisConversationLanguage.speechLocale)',SPEECH)
        self.assertIn("request.requiresOnDeviceRecognition = true",SPEECH)
        self.assertIn("request.shouldReportPartialResults = true",SPEECH)
        self.assertIn("request.taskHint = .dictation",SPEECH)
        self.assertIn("request.contextualStrings = JarvisSpeechVocabulary.phrases",SPEECH)
        self.assertIn("JarvisSpeechVocabulary",VOCAB)
        self.assertIn('"자비스"',VOCAB)
        self.assertIn('"DECHIVE"',VOCAB)
        self.assertIn('"GitHub"',VOCAB)
        self.assertNotIn("replacingOccurrences",VOCAB)
        self.assertNotIn("UserDefaults",VOCAB)

    def test_show_actual_input_device_without_recording_audio(self):
        self.assertIn('AVCaptureDevice.default(for: .audio)?.localizedName',SPEECH)
        self.assertIn('activeMicrophone = "Mac 입력:',SPEECH)
        self.assertIn("self.activeMicrophone = self.listener.activeMicrophone",CHAT)
        self.assertIn('accessibilityIdentifier("jarvis-active-microphone")',OVERLAY)
        self.assertIn('accessibilityIdentifier("jarvis-workspace-active-microphone")',OVERLAY)
        self.assertNotIn("FileHandle(forWritingTo:",SPEECH)
        self.assertNotIn("AVAudioFile(",SPEECH)

if __name__=="__main__":unittest.main()
