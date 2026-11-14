"""Native project workflow must require explicit approval before GitHub reads."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SWIFT = ROOT / "macos/Sources/EidisMac/ApprovedProjectsPanel.swift"
ENTRY = ROOT / "macos/Sources/EidisMac/EidisMacApp.swift"


class ApprovedProjectWorkContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = SWIFT.read_text(encoding="utf-8")
        cls.entry = ENTRY.read_text(encoding="utf-8")

    def test_has_dedicated_native_work_tab(self):
        self.assertIn("ApprovedProjectsPanel()", self.entry)
        self.assertIn('Label("작업", systemImage: "checklist")', self.entry)

    def test_external_check_is_only_in_approved_action(self):
        self.assertIn('func runApprovedCheck(_ proposal: WorkCheckProposal)', self.work)
        self.assertIn('Button("승인하고 공개 GitHub 1회 조회")', self.work)
        self.assertIn("confirmationDialog(", self.work)
        self.assertEqual(self.work.count('fetch("/api/projects/github/check", body: body)'), 1)
        refresh = self.work.split("func refresh() async {", 1)[1].split(
            "func runApprovedCheck", 1)[0]
        self.assertIn('fetch("/api/projects")', refresh)
        self.assertNotIn("github/check", refresh)

    def test_approval_scope_and_read_only(self):
        self.assertIn("$0.repoFullName == proposal.repository", self.work)
        self.assertIn("$0.name == proposal.projectName", self.work)
        self.assertIn("response.receipt.projectId == proposal.projectId", self.work)
        self.assertIn("자동 재시도하지 않았습니다", self.work)
        self.assertIn("파일 변경·푸시·배포·삭제는 하지 않습니다", self.work)
        for prohibited in ("shell.exec", "AXUIElementPerformAction",
                           "AXUIElementSetAttributeValue", "git push", "aws deploy"):
            self.assertNotIn(prohibited, self.work)


if __name__ == "__main__":
    unittest.main()
