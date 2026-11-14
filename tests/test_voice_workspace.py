"""Native voice and typed command project routing remains opt-in and local."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PARSER = ROOT / "macos/Sources/EidisMac/JarvisWorkspaceCommand.swift"
SPEECH = ROOT / "macos/Sources/EidisMac/NativeSpeech.swift"
APP = ROOT / "macos/Sources/EidisMac/EidisMacApp.swift"
WORK = ROOT / "macos/Sources/EidisMac/ApprovedProjectsPanel.swift"
PANEL = ROOT / "macos/Sources/EidisMac/WorkspaceResumePanel.swift"


class VoiceWorkspaceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parser = PARSER.read_text(encoding="utf-8")
        cls.speech = SPEECH.read_text(encoding="utf-8")
        cls.app = APP.read_text(encoding="utf-8")
        cls.work = WORK.read_text(encoding="utf-8")
        cls.panel = PANEL.read_text(encoding="utf-8")

    def test_native_voice_and_typed_commands_route_to_work_tab(self):
        self.assertIn("JarvisWorkspaceCommandParser.parse(trimmed, projects: projectWork.projects)", self.speech)
        self.assertIn("sendCommand(phrase)", self.speech)
        self.assertIn("onWorkspaceRequest(request)", self.speech)
        self.assertIn("onWorkspaceRequest: { request in", self.app)
        self.assertIn("workspaceRequest = request", self.app)
        self.assertIn("selectedTab = .work", self.app)
        self.assertIn("TabView(selection: $selectedTab)", self.app)
        self.assertIn("ApprovedProjectsPanel(work: projectWork, requestedWorkspace: workspaceRequest)", self.app)
        self.assertIn("applyRequestedProject()", self.work)
        self.assertIn("applyRoutedRequest()", self.panel)

    def test_safe_execution_boundary(self):
        self.assertIn("case .missingProject", self.speech)
        self.assertIn("case .ambiguous", self.speech)
        self.assertIn("case .unsupported", self.speech)
        self.assertIn("case .matched(let request)", self.speech)
        self.assertIn('workspaceProposal = JarvisWorkspaceResume.prepare(', self.panel)
        self.assertIn('Button("승인하고 선택한 작업 공간 1회 열기")', self.panel)
        self.assertEqual(self.panel.count("work.openApprovedWorkspace(proposal)"), 1)
        self.assertNotIn("NSWorkspace.shared.open", self.speech)
        self.assertNotIn("NSWorkspace.shared.open", self.parser)
        for action in ["push", "commit", "배포", "삭제", "결제"]:
            self.assertIn(action, self.parser)
        self.assertNotIn("URLSession", self.parser)

    def test_regular_chat_retained(self):
        self.assertIn("case .ordinary:", self.speech)
        self.assertIn("await client.submit(trimmed", self.speech)
        self.assertIn("remote_consent", self.speech)
        self.assertIn("onChange(of: requestedWorkspace?.id)", self.work)
        self.assertIn("onChange(of: requestedWorkspace?.id)", self.panel)


if __name__ == "__main__":
    unittest.main()
