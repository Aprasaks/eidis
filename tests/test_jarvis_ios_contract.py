"""EIDIS 0.4 iOS native privacy, real data and routing contract."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "ios"
SRC = IOS / "JARVIS" / "Sources"
CAMERA = (SRC / "JARVISCamera.swift").read_text()
VOICE = (SRC / "JARVISVoice.swift").read_text()
HOME = (SRC / "JARVISHomeView.swift").read_text()
COMMAND = (SRC / "EIDISCommand.swift").read_text()
REPLY = (SRC / "JARVISResponse.swift").read_text()
WEATHER = (SRC / "EIDISWeather.swift").read_text()
PERSONAL = (SRC / "EIDISPersonalData.swift").read_text()
SERVICE = (SRC / "EIDISServiceSheet.swift").read_text()
PROJECT = (IOS / "JARVIS.xcodeproj" / "project.pbxproj").read_text()


class EIDISV04ContractTests(unittest.TestCase):
    def test_physical_camera_permissions_and_existing_controls(self):
        for token in ("AVCaptureDevice.requestAccess", "targetEnvironment(simulator)",
                      "builtInWideAngleCamera", "session.startRunning()",
                      "session.stopRunning()"):
            self.assertIn(token, CAMERA)
        self.assertIn("camera.start()", HOME)
        self.assertIn("camera.stop()", HOME)
        self.assertIn("JARVISCameraPreview(session: camera.session)", HOME)

    def test_on_device_speech_still_explicit_and_routed(self):
        for token in ('SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))',
                      "recognizer.supportsOnDeviceRecognition",
                      "request.requiresOnDeviceRecognition = true",
                      "request.contextualStrings = EIDISCommand.hints",
                      "SFSpeechRecognizer.requestAuthorization",
                      "AVAudioApplication.requestRecordPermission()",
                      "func cancel()", "sessionID = UUID()",
                      "func finish() async -> String?",
                      "audioRequest?.endAudio()", "AVSpeechSynthesizer()",
                      "func speak(_ response: String, for recognized: String)"):
            self.assertIn(token, VOICE)
        for token in ('"애기야"', '"아기야"', 'case weather',
                      'case calendar', 'case reminders'):
            self.assertIn(token, COMMAND)
        self.assertIn("if let command = await voice.finish()", HOME)
        self.assertIn("await handleCommand(command)", HOME)
        self.assertIn("voice.speak(answer, for: command)", HOME)

    def test_native_service_permissions_and_presentation(self):
        for token in ("requestFullAccessToEvents()", "requestFullAccessToReminders()",
                      "EKEventStore.authorizationStatus", "predicateForEvents",
                      "predicateForReminders", "fetchReminders(matching: predicate)"):
            self.assertIn(token, PERSONAL)
        for token in ("CLLocationManager", "requestWhenInUseAuthorization()",
                      "requestLocation()", "https://api.open-meteo.com/v1/forecast",
                      "temperature_2m", "weather_code",
                      "URLSession.shared.data(for: request)",
                      "loadWttr(coordinate: coordinate)", "https://api.open-meteo.com/v1/forecast",
                      "wttr.in", "current_condition", "conditionOverride"):
            self.assertIn(token, WEATHER)
        for token in ("activeService = .weather", "activeService = .calendar",
                      "activeService = .reminders", "EIDISServiceSheet(",
                      "weather.displayValue", "personal.calendarStatus",
                      "personal.remindersStatus"):
            self.assertIn(token, HOME)
        for token in ("connectOrRefresh()", "connectCalendar()",
                      "connectReminders()", "Open-Meteo"):
            self.assertIn(token, SERVICE)

    def test_truthful_state_and_no_fake_server_ai(self):
        for token in ('"개인 AI", "연결 전"',
                      '"카메라 사물 분석", "연결 전"',
                      '"Mac 프로젝트 기억", "연결 전"',
                      'today ='):
            if token == 'today =':
                self.assertNotIn(token, HOME)
            else:
                self.assertIn(token, HOME)
        self.assertIn('"탭하여 연결"', PERSONAL)
        self.assertIn('"탭하여 연결"', WEATHER)
        for text in ("오늘 첫 일정 09:30", "다음 일정까지 18분",
                     "시내버스 470", "AI 분석 성공", "api.openai.com",
                     "api.elevenlabs.io", "api.anthropic.com"):
            self.assertNotIn(text, HOME + WEATHER + PERSONAL + SERVICE)

    def test_release_ios_entitlements_and_names(self):
        for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                    "NSSpeechRecognitionUsageDescription",
                    "NSCalendarsFullAccessUsageDescription",
                    "NSRemindersFullAccessUsageDescription",
                    "NSLocationWhenInUseUsageDescription"):
            self.assertIn(key, PROJECT)
        for name in ("EIDISCommand.swift", "EIDISWeather.swift",
                     "EIDISPersonalData.swift", "EIDISCoreView.swift",
                     "EIDISServiceSheet.swift"):
            self.assertIn(name, PROJECT)
        self.assertIn("INFOPLIST_KEY_CFBundleDisplayName = EIDIS;", PROJECT)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = dev.dechive.jarvis.ios;", PROJECT)
        self.assertIn("MARKETING_VERSION = 0.4.1;", PROJECT)
        self.assertIn("CURRENT_PROJECT_VERSION = 5;", PROJECT)
        self.assertTrue((IOS / "EIDIS/Assets.xcassets/AppIcon.appiconset/AppIcon.png").is_file())


if __name__ == "__main__":
    unittest.main()
