"""Native task-start flow is deliberately scoped and approval-gated."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORK = (ROOT / "macos/Sources/EidisMac/ApprovedProjectsPanel.swift").read_text("utf-8")


class TaskStartContractTests(unittest.TestCase):
    def test_explicit_confirmation_before_local_write(self):
        self.assertIn('Button("이 작업 시작 제안")', WORK)
        self.assertIn('Button("시작 승인 화면")', WORK)
        self.assertIn('Button("승인하고 이 작업 시작 기록")', WORK)
        self.assertIn('Button("취소", role: .cancel) { taskStartProposal = nil }', WORK)
        self.assertIn("if await work.beginApprovedTask(proposal)", WORK)
        self.assertIn("let age = Date().timeIntervalSince(proposal.createdAt)", WORK)
        self.assertIn("(0...120).contains(age)", WORK)

    def test_server_freshness_and_receipt_guard(self):
        source = WORK.split("func beginApprovedTask(", 1)[1].split(
            "func runApprovedCheck(", 1)[0]
        self.assertLess(source.index('fetch("/api/projects")'),
                        source.index('fetch(\n                "/api/projects/status"'))
        self.assertIn("$0.name == proposal.projectName", source)
        self.assertIn("$0.repoFullName == proposal.repository", source)
        self.assertIn('$0.title == proposal.taskTitle &&', source)
        self.assertIn('$0.status == "todo"', source)
        self.assertIn('$0.status == "doing"', source)
        self.assertIn('"task_id": proposal.taskId', source)
        self.assertIn('"status": "doing"', source)
        self.assertIn("자동 재시도하지 않습니다", source)
        self.assertIn("return true", source)

    def test_start_does_not_open_or_modify_files(self):
        source = WORK.split("func beginApprovedTask(", 1)[1].split(
            "func runApprovedCheck(", 1)[0]
        for forbidden in ("NSWorkspace.shared.open", "git push", "git commit",
                          "Process()", "AXUIElementPerformAction", "api.github.com",
                          "aws deploy"):
            self.assertNotIn(forbidden, source)
        self.assertIn("taskWorkspaceRequest = JarvisWorkspaceCommand(", WORK)
        self.assertIn("WorkspaceResumePanel(", WORK)
        self.assertIn("requestedWorkspace: taskWorkspaceRequest?.projectId", WORK)


if __name__ == "__main__":
    unittest.main()
