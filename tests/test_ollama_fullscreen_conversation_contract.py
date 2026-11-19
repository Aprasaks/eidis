from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = (ROOT / 'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
CHAT = (ROOT / 'macos/Sources/EidisMac/JarvisOverlayConversation.swift').read_text()
ELEVEN = (ROOT / 'macos/Sources/EidisMac/ElevenLabsVoiceService.swift').read_text()
SPEECH = (ROOT / 'macos/Sources/EidisMac/NativeSpeech.swift').read_text()
PLIST = (ROOT / 'macos/Resources/Info.plist').read_text()

class OllamaFullscreenConversationContract(unittest.TestCase):
    def test_local_model_only_not_remote_brain(self):
        for needle in ['http://127.0.0.1:11434/api/chat', 'qwen3.5:9b-q4_K_M',
                       '"think": false', '"stream": false', '"num_predict": 150',
                       'URLSessionConfiguration.ephemeral', 'conversation.suffix(8)',
                       'conversation.removeAll()', 'conversation.count > 8']:
            self.assertIn(needle, CHAT)
        self.assertNotIn('api.openai.com', CHAT)
        self.assertNotIn('api.anthropic.com', CHAT)
        self.assertNotIn('FileHandle(forWritingTo:', CHAT)
        self.assertNotIn('Process()', CHAT)
    def test_microphone_esc_and_utterance_turns(self):
        for needle in ['LocalSpeechListener()', 'listener.start()', 'listener.finish()',
                       'listener.cancel()', 'isListening', 'afterGreeting()',
                       'if isActive { activateListening() }',
                       'session.invalidateAndCancel()', 'generation = UUID()',
                       'SFSpeechRecognizer.authorizationStatus()',
                       'AVCaptureDevice.authorizationStatus(for: .audio)']:
            self.assertIn(needle, CHAT)
        for needle in ['dialogue?.cancel()', 'speakSummonGreeting',
                       'waitForOutputToFinish', 'await dialogue.afterGreeting()',
                       'if event.keyCode == 53', 'dialogue?.toggleMicrophone()',
                       'jarvis-overlay-microphone', 'jarvis-overlay-text-input',
                       '.focused($isInputFocused)', 'dialogue.textInputFocused = focused',
                       'self.dialogue?.textInputFocused != true',
                       'window.orderOut(nil)', 'videoURL: url',
                       'RegisterEventHotKey(UInt32(kVK_Escape)',
                       'hotkey?.uninstallEscape()', 'case 52: key.onEscape?()']:
            self.assertIn(needle, OVERLAY)
        self.assertIn('requiresOnDeviceRecognition = true', SPEECH)
        self.assertIn('waitForOutputToFinish(fallback:', ELEVEN)
    def test_existing_behaviors_and_permissions_preserved(self):
        self.assertIn('JARVIS_FullHD_Loop', OVERLAY)
        self.assertIn('moveToAdjacentScreen', OVERLAY)
        self.assertIn('NSSpeechRecognitionUsageDescription', PLIST)
        self.assertIn('NSMicrophoneUsageDescription', PLIST)
        self.assertIn('<string>3.10.2</string>', PLIST)

if __name__ == '__main__':
    unittest.main()
