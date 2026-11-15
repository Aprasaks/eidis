"""JARVIS HUD v0.2 regression contract: cinematic but not deceptive."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOME = (ROOT / 'ios/JARVIS/Sources/JARVISHomeView.swift').read_text()
CAMERA = (ROOT / 'ios/JARVIS/Sources/JARVISCamera.swift').read_text()
VOICE = (ROOT / 'ios/JARVIS/Sources/JARVISVoice.swift').read_text()


class JarvisHUDV02Tests(unittest.TestCase):
    def test_cinematic_design_and_camera_first_content(self):
        for marker in ('private enum HUDStyle', 'private struct HUDGlass',
                       'private struct HUDReticle', 'private struct HUDBackdrop',
                       'private struct HUDService', 'private struct HUDWaveform',
                       'JARVISCameraPreview(session: camera.session)',
                       'HUDReticle(cameraLive: camera.isLive)',
                       'camera.isLive', '.strokeBorder(HUDStyle.glassStroke'):
            self.assertIn(marker, HOME)

    def test_fixed_voice_and_camera_controls_still_wired(self):
        for marker in ('@StateObject private var camera = JARVISCamera()',
                       '@StateObject private var voice = JARVISVoice()',
                       'voice.finish()', 'voice.start()', 'voice.cancel()',
                       'voice.respond(to: command)',
                       'voice.stopSpeaking()', 'camera.start()', 'camera.stop()',
                       'showComposer = true', 'showFeatures = true',
                       'showTranscript = true'):
            self.assertIn(marker, HOME)
        self.assertIn('func finish() async', VOICE)
        self.assertIn('func stop()', CAMERA)

    def test_disconnected_services_not_animated_as_live_ai(self):
        for marker in ('value: "연결 전"', 'Text("물체 분석 연결 전")',
                       'Text("ON-DEVICE VOICE  ·  AI 연결 전")',
                       '"Mac JARVIS 기억", "연결 전"',
                       '"카메라 사물 분석", "연결 전"',
                       'cameraLive ? "LIVE VIEW" : "STANDBY"'):
            self.assertIn(marker, HOME)
        for forbidden in ('AI 활성화', '실시간 분석 중',
                          '오늘 첫 일정 09:30', '다음 일정까지 18분',
                          '12°C', '시내버스 470', 'api.openai.com',
                          'URLSession.shared', 'AI 분석 성공'):
            self.assertNotIn(forbidden, HOME)

    def test_camera_and_mic_stop_in_background(self):
        self.assertIn('@Environment(\\.scenePhase) private var scenePhase', HOME)
        self.assertIn('.onChange(of: scenePhase) { _, phase in', HOME)
        self.assertIn('if phase != .active', HOME)
        self.assertIn('camera.stop()', HOME)
        self.assertIn('voice.cancel()', HOME)

    def test_accessibility_and_not_only_decorative_buttons(self):
        for marker in ('"음성 녹음 완료" : "음성 시작"',
                       'accessibilityLabel("기능 연결 상태 보기")',
                       '"카메라 끄기" : "카메라"',
                       'accessibilityLabel("인식된 문장과 자비스 응답 전체 보기")',
                       '.disabled(voice.busy)',
                       'func sendTyped()'):
            self.assertIn(marker, HOME)


if __name__ == '__main__':
    unittest.main()
