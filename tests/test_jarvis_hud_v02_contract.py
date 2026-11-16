"""EIDIS 0.3 visual and action tests: real matte-black native controls."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOME = (ROOT / "ios/JARVIS/Sources/JARVISHomeView.swift").read_text()
CAMERA = (ROOT / "ios/JARVIS/Sources/JARVISCamera.swift").read_text()
VOICE = (ROOT / "ios/JARVIS/Sources/JARVISVoice.swift").read_text()


class EIDISBlackV03Tests(unittest.TestCase):
    def test_black_matte_ui_instead_of_glowing_glass(self):
        for text in ("private enum EIDISLook", "private struct EIDISCard",
                     "private struct EIDISBackdrop", "private struct EIDISFocus",
                     "static let black = Color(", "static let panel = Color(",
                     "Text(\"EIDIS\")", "Text(\"LOCAL\")"):
            self.assertIn(text, HOME)
        for rejected in ("ultraThinMaterial", "HUDGlass", "HUDReticle",
                         "HUDBackdrop", "HUDWaveform", "Image(systemName: \"sparkle\")",
                         "Image(systemName: \"sparkles\")", ".shadow(",
                         "실시간 분석 중", "오늘 첫 일정 09:30", "다음 일정까지 18분",
                         "12°C", "시내버스 470"):
            self.assertNotIn(rejected, HOME)

    def test_controls_remain_connected(self):
        for item in ('@StateObject private var camera = JARVISCamera()',
                     '@StateObject private var voice = JARVISVoice()',
                     'camera.start()', 'camera.stop()', 'voice.start()',
                     'voice.finish()', 'voice.cancel()', 'voice.stopSpeaking()',
                     'voice.respond(to: command)', 'showComposer = true',
                     'showFeatures = true', 'showTranscript = true',
                     'JARVISCameraPreview(session: camera.session)'):
            self.assertIn(item, HOME)

    def test_camera_mic_stopped_in_background(self):
        self.assertIn('@Environment(\\.scenePhase) private var scenePhase', HOME)
        self.assertIn('.onChange(of: scenePhase) { _, phase in', HOME)
        self.assertIn('if phase != .active', HOME)
        self.assertIn('camera.stop()', HOME)
        self.assertIn('voice.cancel()', HOME)

    def test_status_truth_and_accessibility(self):
        for text in ('value: "연결 전"', '"Mac 프로젝트 기억", "연결 전"',
                     '"카메라 사물 분석", "연결 전"',
                     'accessibilityLabel("기능 연결 상태 보기")',
                     'accessibilityLabel("인식된 문장과 EIDIS 응답 전체 보기")',
                     '.disabled(voice.busy)',
                     'func sendTyped()', "AI 연결 전"):
            self.assertIn(text, HOME)


if __name__ == "__main__":
    unittest.main()
