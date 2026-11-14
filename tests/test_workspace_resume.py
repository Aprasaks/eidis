"""User-approved workspace opening: bounded destination, no implicit actions."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXECUTOR = ROOT / "macos/Sources/EidisMac/JarvisWorkspaceResume.swift"
PANEL = ROOT / "macos/Sources/EidisMac/WorkspaceResumePanel.swift"
WORK = ROOT / "macos/Sources/EidisMac/ApprovedProjectsPanel.swift"


class WorkspaceResumeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.executor = EXECUTOR.read_text(encoding="utf-8")
        cls.panel = PANEL.read_text(encoding="utf-8")
        cls.work = WORK.read_text(encoding="utf-8")

    def test_open_only_after_explicit_user_confirmation(self):
        self.assertIn('Button("승인하고 선택한 작업 공간 1회 열기")', self.panel)
        self.assertIn('Button("작업 이어하기 제안 만들기")', self.panel)
        self.assertIn('Button("열기 작업 1회 승인 화면")', self.panel)
        self.assertIn('Button("취소", role: .cancel)', self.panel)
        self.assertIn('.alert("선택한 프로젝트 작업 공간을 열까요?"', self.panel)
        self.assertEqual(self.panel.count("work.openApprovedWorkspace(proposal)"), 1)
        self.assertIn('workspaceProposal = nil', self.panel)
        self.assertNotIn("NSWorkspace.shared.open", self.panel)

    def test_destinations_are_strictly_scoped(self):
        self.assertIn('components.scheme = "https"', self.executor)
        self.assertIn('components.host = "github.com"', self.executor)
        self.assertIn('url.query == nil, url.fragment == nil', self.executor)
        self.assertIn('project.id == proposal.projectId', self.executor)
        self.assertIn('project.repoFullName == proposal.repository', self.executor)
        self.assertIn('currentLinkedFolder == folder', self.executor)
        self.assertIn('(0...120).contains(age)', self.executor)
        self.assertIn('resolvingSymlinksInPath()', self.executor)
        self.assertIn('appendingPathComponent(".git")', self.executor)

    def test_native_open_does_not_write_or_execute_code(self):
        self.assertEqual(self.work.count("NSWorkspace.shared.open($0)"), 1)
        self.assertIn('WorkspaceResumePanel(', self.work)
        self.assertIn('requestedWorkspace: taskWorkspaceRequest?.projectId == selected.id', self.work)
        self.assertIn('(requestedWorkspace?.projectId == selected.id', self.work)
        for forbidden in [
            "Process()", "system(", "osascript", "git push", "git commit",
            "URLSession", "write(to:", "AXUIElementPerformAction",
            "FileManager.default.removeItem"
        ]:
            self.assertNotIn(forbidden, self.executor)
        self.assertIn('실제 페이지 로딩이나 폴더 내용 확인을 뜻하지 않습니다.', self.executor)


if __name__ == "__main__":
    unittest.main()
