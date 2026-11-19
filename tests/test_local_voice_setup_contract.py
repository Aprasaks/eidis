from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "macos/Sources/EidisMac/JarvisVoiceSetupView.swift").read_text()
APP = (ROOT / "macos/Sources/EidisMac/EidisMacApp.swift").read_text()

class LocalVoiceSetupContract(unittest.TestCase):
    def test_manual_recording_and_private_files(self):
        for marker in ('AVAudioRecorder', 'AVCaptureDevice.requestAccess(for: .audio)',
                       'func startRecording() async', 'func stopRecording()',
                       'Library/Application Support/DECHIVE-JARVIS/voice-clone',
                       'generate_clone.py', 'HF_HUB_OFFLINE', '--reference-text',
                       'Button("내 목소리 녹음")'):
            if marker == 'Button("내 목소리 녹음")':
                self.assertIn('"내 목소리 녹음"', VIEW)
            else:
                self.assertIn(marker, VIEW)
        self.assertNotIn('https://', VIEW)
    def test_default_window_stays_suppressed(self):
        self.assertIn('Window("내 목소리 설정", id: "jarvis-voice-setup")', APP)
        self.assertEqual(APP.count('.defaultLaunchBehavior(.suppressed)'), 3)
        self.assertIn('openWindow(id: "jarvis-voice-setup")', APP)
        self.assertIn('Button("내 목소리 설정")', APP)

if __name__ == '__main__': unittest.main()
