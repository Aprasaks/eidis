"""Check explicit approved Markdown note writing boundaries in native Mac code."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORK = (ROOT / "macos/Sources/EidisMac/ApprovedProjectsPanel.swift").read_text("utf-8")
NOTE = (ROOT / "macos/Sources/EidisMac/JarvisTaskNote.swift").read_text("utf-8")
CI = (ROOT / ".github/workflows/ci.yml").read_text("utf-8")


class TaskNoteContractTests(unittest.TestCase):
    def test_explicit_preview_then_approval(self):
        self.assertIn('Button("실행 메모")', WORK)
        self.assertIn('Button("Markdown 저장 내용 미리보기")', WORK)
        self.assertIn('Button("메모 파일 저장 승인 화면")', WORK)
        self.assertIn('Button("승인하고 새 메모 파일 저장")', WORK)
        self.assertIn('Button("취소", role: .cancel) { taskNoteProposal = nil }', WORK)
        self.assertIn("JarvisTaskNote.prepare(", WORK)
        self.assertIn("if let taskNoteProposal", WORK)
        self.assertIn("Task { _ = await work.saveApprovedTaskNote(proposal) }", WORK)
        self.assertIn("taskNoteProposal = nil", WORK)

    def test_fresh_local_project_and_linked_folder_before_write(self):
        section = WORK.split("func saveApprovedTaskNote(", 1)[1].split(
            "func runApprovedCheck(", 1)[0]
        self.assertIn('fetch("/api/projects")', section)
        self.assertIn("$0.name == proposal.projectName", section)
        self.assertIn("$0.repoFullName == proposal.repository", section)
        self.assertIn("localFolder(projectId: proposal.projectId)", section)
        self.assertIn("JarvisTaskNote.save(", section)
        self.assertIn("currentLinkedFolder: folder", section)
        self.assertIn("다른 경로에 자동 재시도하지 않습니다.", section)
        self.assertNotIn("NSWorkspace.shared.open", section)
        self.assertNotIn("/api/projects/status", section)

    def test_file_is_new_and_verified_and_path_is_bounded(self):
        for token in (
            "O_NOFOLLOW", "O_EXCL", "O_DIRECTORY", "openat(", "mkdirat(",
            "fstatat(", "AT_SYMLINK_NOFOLLOW", "fsync(file)",
            "actual == bytes", "unlinkat(", "timeIntervalSince(proposal.createdAt)",
            "project.repoFullName == proposal.repository",
            "$0.status == proposal.taskStatus",
        ):
            self.assertIn(token, NOTE)
        self.assertIn('".jarvis/notes/', NOTE)
        self.assertIn("case alreadyExists", NOTE)
        self.assertIn("case cannotVerify", NOTE)
        for forbidden in ("git push", "git commit", "Process()", "URLSession(",
                          "NSWorkspace.shared.open", "AXUIElementPerformAction"):
            self.assertNotIn(forbidden, NOTE)

    def test_ci_compiles_new_native_file(self):
        self.assertEqual(CI.count("macos/Sources/EidisMac/JarvisTaskNote.swift"), 2)


if __name__ == "__main__":
    unittest.main()
