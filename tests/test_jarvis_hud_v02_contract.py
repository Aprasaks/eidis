"""EIDIS 0.4 HUD and user-driven permission contracts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "ios/JARVIS/Sources"
HOME = (SRC / "JARVISHomeView.swift").read_text()
CORE = (SRC / "EIDISCoreView.swift").read_text()
WEATHER = (SRC / "EIDISWeather.swift").read_text()
PERSONAL = (SRC / "EIDISPersonalData.swift").read_text()
SERVICE = (SRC / "EIDISServiceSheet.swift").read_text()


class EIDISHUDV04Tests(unittest.TestCase):
    def test_matte_design_and_live_core_replaces_static_center_text(self):
        for token in ("private enum EIDISLook", "private struct EIDISCard",
                      "private struct EIDISBackdrop", "EIDISCoreView(",
                      "active: scenePhase == .active", "static let black = Color(",
                      "static let panel = Color("):
            self.assertIn(token, HOME)
        for token in ("struct EIDISCoreView", "rotationEffect(",
                      "repeatForever(autoreverses: false)",
                      ".accessibilityReduceMotion", "cameraLive",
                      "listening", "active"):
            self.assertIn(token, CORE)
        for disallowed in ("ultraThinMaterial", "HUDGlass", "HUDWaveform",
                           'Image(systemName: "sparkle")',
                           'Image(systemName: "sparkles")',
                           "private struct EIDISFocus",
                           "TimelineView(.animation"):
            self.assertNotIn(disallowed, HOME)

    def test_existing_camera_and_voice_controls_wired(self):
        for token in ("@StateObject private var camera = JARVISCamera()",
                      "@StateObject private var voice = JARVISVoice()",
                      "voice.finish()", "voice.start()", "voice.cancel()",
                      "voice.stopSpeaking()", "camera.start()", "camera.stop()",
                      "showComposer = true", "showFeatures = true",
                      "showTranscript = true", "func sendTyped()",
                      ".disabled(voice.busy)"):
            self.assertIn(token, HOME)
        self.assertIn("voice.speak(answer, for: command)", HOME)
        self.assertIn('Text("EIDIS")', HOME)

    def test_background_safety_and_explicit_service_permission(self):
        self.assertIn('@Environment(\\.scenePhase) private var scenePhase', HOME)
        self.assertIn(".onChange(of: scenePhase) { _, phase in", HOME)
        self.assertIn("if phase != .active", HOME)
        self.assertIn("camera.stop()", HOME)
        self.assertIn("voice.cancel()", HOME)
        self.assertIn(".task {", HOME)
        self.assertIn("await personal.refreshAuthorized()", HOME)
        self.assertNotIn("await personal.connectCalendar()", HOME)
        self.assertNotIn("await personal.connectReminders()", HOME)
        self.assertIn("Button { activeService = .weather }", HOME)
        self.assertIn("Button { activeService = .calendar }", HOME)
        self.assertIn("Button { activeService = .reminders }", HOME)
        self.assertIn("Button {", SERVICE)
        self.assertIn("Task { await personal.connectCalendar() }", SERVICE)
        self.assertIn("Task { await personal.connectReminders() }", SERVICE)
        self.assertIn("weather.connectOrRefresh()", SERVICE)

    def test_no_silent_location_upload_or_editing_personal_data(self):
        self.assertIn("func connectOrRefresh()", WEATHER)
        self.assertIn("explicitlyRequested = true", WEATHER)
        self.assertIn("guard explicitlyRequested, busy else { return }", WEATHER)
        self.assertIn("https://api.open-meteo.com/v1/forecast", WEATHER)
        for forbidden in ("store.save(", "store.remove(", "removeCalendar(",
                          "saveEvent(", "removeReminder(", "saveReminder("):
            self.assertNotIn(forbidden, PERSONAL)
        self.assertIn("미리 알림", SERVICE)
        self.assertIn("Apple 캘린더", SERVICE)


if __name__ == "__main__":
    unittest.main()
