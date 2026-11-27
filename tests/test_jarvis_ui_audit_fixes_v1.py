"""2026-11-27 전면 UI 점검 수정 계약 (소스 텍스트 기준)."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAC = ROOT / "macos/Sources/EidisMac"
IOS = ROOT / "ios/JARVIS/Sources"


def read(path):
    return path.read_text(encoding="utf-8")


class UiAuditFixes(unittest.TestCase):
    def test_sns_room_state_lives_in_model(self):
        self.assertIn("@Published var snsRoomOpen = false", read(MAC / "JarvisLiveDashboard.swift"))
        center = read(MAC / "JarvisCommandCenterView.swift")
        self.assertIn("nonmutating set { model.snsRoomOpen = newValue }", center)
        self.assertIn(".accessibilityHidden(model.workroomProject != nil || showChannelOverview)", center)
        overlay = read(MAC / "JarvisFullscreenOverlay.swift")
        self.assertIn("liveDashboard.workroomProject == nil && !liveDashboard.snsRoomOpen", overlay)

    def test_close_button_is_visible(self):
        center = read(MAC / "JarvisCommandCenterView.swift")
        self.assertIn('Text("코어로 · esc")', center)
        self.assertIn(".contentShape(Capsule())", center)

    def test_system_noise_hidden(self):
        bay = read(MAC / "JarvisAgentTerminalBay.swift")
        self.assertIn('guard item["subtype"] as? String == "init" else { return "" }', bay)

    def test_iphone_back_and_connect(self):
        home = read(IOS / "JARVISHomeView.swift")
        self.assertIn('static let tabPages: Set<JARVISMobilePage> = [.core, .dashboard, .alarm, .calendar, .memory]', home)
        self.assertIn('accessibilityLabel("전체 현황으로 돌아가기")', home)
        self.assertIn("value.startLocation.x < 32", home)
        self.assertIn('Label("Mac 연결하기 · 12자리 코드", systemImage: "link")', read(IOS / "JARVISMobileSocialView.swift"))

    def test_team_id_not_committed(self):
        project = read(ROOT / "ios/JARVIS.xcodeproj/project.pbxproj")
        self.assertNotIn("Z63TP6ZRVH", project)
        self.assertIn('#include? "JARVISRemote.local.xcconfig"', read(ROOT / "ios/JARVISRemote.xcconfig"))


if __name__ == "__main__":
    unittest.main()
