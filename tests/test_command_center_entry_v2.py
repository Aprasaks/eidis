from pathlib import Path
import unittest
S=Path(__file__).resolve().parents[1]/"macos/Sources/EidisMac"
UI=(S/"JarvisCommandCenterView.swift").read_text()
OVER=(S/"JarvisFullscreenOverlay.swift").read_text()
MENU=(S/"EidisMacApp.swift").read_text()
CONV=(S/"JarvisOverlayConversation.swift").read_text()
DATA=(S/"JarvisLiveDashboard.swift").read_text()
class CommandCenterEntry(unittest.TestCase):
    def test_direct_entry_not_voice_or_llm(self):
        self.assertIn('Button("전체 대시보드 열기") { fullscreen.openCommandCenter() }',MENU)
        self.assertIn('present(fullscreenDialogue: miniDialogue, silent: true)',OVER)
        self.assertIn('if silent {',OVER)
        self.assertIn('if continuingActiveTurn {',OVER)
        self.assertIn('await voice.openCommandCenterDirectly()',OVER)
        self.assertIn('await liveDashboard.show(.overview)',CONV)
    def test_status_not_blanket_online(self):
        for name in ["githubSnapshot","vercelSnapshot","youtubeSummary","instagramSnapshot","ollamaVersion"]:
            self.assertIn(name,UI.split("private var allSourcesHealthy",1)[1].split("private func sourceRow",1)[0])
        self.assertIn("CHECK SOURCE STATUS",UI)
        self.assertIn("checkedAt: model.githubSnapshot?.checkedAt",UI)
    def test_refresh_no_overlap_and_preserve_remote_cooldowns(self):
        self.assertIn("await model.refreshVisible()",UI)
        self.assertIn("guard isVisible, !isRefreshing else { return }",DATA)
        self.assertIn("revision == id && !Task.isCancelled && !isRefreshing",DATA)
        self.assertIn("githubRefreshSeconds: TimeInterval = 600",DATA)
        self.assertIn("vercelRefreshSeconds: TimeInterval = 900",DATA)
if __name__=="__main__":unittest.main()
