"""JARVIS iPhone v0.1 privacy/build contract; physical TCC is separate."""
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "ios"
SOURCES = IOS / "JARVIS" / "Sources"
CAMERA = (SOURCES / "JARVISCamera.swift").read_text()
VOICE = (SOURCES / "JARVISVoice.swift").read_text()
HOME = (SOURCES / "JARVISHomeView.swift").read_text()
REPLY = (SOURCES / "JARVISResponse.swift").read_text()
PROJECT = (IOS / "JARVIS.xcodeproj" / "project.pbxproj").read_text()


class JARVISiOSContractTests(unittest.TestCase):
    def test_camera_explicit_permission_and_simulator_truth(self):
        for token in ["AVCaptureDevice.requestAccess", "targetEnvironment(simulator)",
                      "시뮬레이터에는 카메라가 없습니다", "builtInWideAngleCamera",
                      "func stop()", "session.stopRunning()", "session.startRunning()"]:
            self.assertIn(token, CAMERA)
        self.assertIn('camera.start()', HOME)
        self.assertIn('camera.stop()', HOME)
        self.assertIn("HUD PREVIEW", HOME)
        self.assertIn("CAMERA LIVE", HOME)

    def test_on_device_speech_explicit_start_and_cancel(self):
        for token in ["SFSpeechRecognizer(locale: Locale(identifier: \"ko-KR\"))",
                      "recognizer.supportsOnDeviceRecognition",
                      "request.requiresOnDeviceRecognition = true",
                      "SFSpeechRecognizer.requestAuthorization",
                      "AVAudioApplication.requestRecordPermission()",
                      "func cancel()", "sessionID = UUID()",
                      "func finish() async", "audioRequest?.endAudio()",
                      "AVSpeechSynthesizer()"]:
            self.assertIn(token, VOICE)
        self.assertIn("if isRecognitionFinal || recognitionError", VOICE)
        self.assertIn("guard !failed, !content.isEmpty else", VOICE)
        self.assertIn("voice.finish()", HOME)
        self.assertIn("voice.cancel()", HOME)

    def test_no_faked_data_or_remote_send(self):
        for needle in ["연결 전", "HUD PREVIEW", "물체 분석 연결 전", "AI 연결 전"]:
            self.assertIn(needle, HOME)
        for needle in ["아직 iPhone과 동기화되지", "아직 연결되지",
                       "기본 음성 응답"]:
            self.assertIn(needle, REPLY)
        for source in (CAMERA, VOICE, HOME, REPLY):
            for forbidden in ["URLSession.shared.data", "api.openai.com",
                              "api.elevenlabs.io", "http://127.0.0.1:8765",
                              "api.github.com"]:
                self.assertNotIn(forbidden, source)

    def test_native_capabilities_and_project_setup(self):
        for value in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                      "NSSpeechRecognitionUsageDescription", "JARVISResponse.swift",
                      "JARVISVoice.swift", "JARVISCamera.swift",
                      "ASSETCATALOG_COMPILER_APPICON_NAME",
                      "IPHONEOS_DEPLOYMENT_TARGET = 17.0"]:
            self.assertIn(value, PROJECT)
        self.assertTrue((IOS / "JARVIS" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png").is_file())


if __name__ == "__main__":
    unittest.main()
