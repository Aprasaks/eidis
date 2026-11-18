"""Read-only task note library safety and UI contract."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = (ROOT / "macos/Sources/EidisMac/JarvisNoteLibrary.swift").read_text("utf-8")
WORK = (ROOT / "macos/Sources/EidisMac/ApprovedProjectsPanel.swift").read_text("utf-8")
CI = (ROOT / ".github/workflows/ci.yml").read_text("utf-8")


class TaskNoteLibraryContractTests(unittest.TestCase):
    def test_scoped_file_access_no_shell_or_network(self):
        for expected in ("taskId > 0", "O_NOFOLLOW", "O_DIRECTORY",
                         "AT_SYMLINK_NOFOLLOW", "openat(", "fstat(", "fdopendir(",
                         "maxBytes = 16_384", "prefix(20)", "filename: filename"):
            self.assertIn(expected, LIBRARY)
        self.assertIn('".jarvis"', LIBRARY)
        self.assertIn('"notes"', LIBRARY)
        for forbidden in ("Process()", "URLSession(", "NSWorkspace.shared.open",
                          "Darwin.write(", "mkdirat(", "unlinkat(", "git push"):
            self.assertNotIn(forbidden, LIBRARY)

    def test_work_tab_user_chooses_task_and_file(self):
        self.assertIn('Button("저장된 메모")', WORK)
        self.assertIn('Button("메모 보기")', WORK)
        self.assertIn('Button("내용 읽기")', WORK)
        self.assertIn("loadSavedNotes(projectId: Int, taskId: Int)", WORK)
        self.assertIn("readSavedNote(projectId: Int, taskId: Int, filename: String)", WORK)
        self.assertIn("JarvisNoteLibrary.list(", WORK)
        self.assertIn("JarvisNoteLibrary.read(", WORK)
        self.assertIn("savedNoteTaskId == taskId", WORK)
        self.assertIn('Text(work.savedNoteText)', WORK)
        self.assertIn('if noteTask.status == "doing" || noteTask.status == "todo"', WORK)

    def test_ci_includes_implementation_in_both_native_compiles(self):
        self.assertEqual(CI.count("macos/Sources/EidisMac/JarvisNoteLibrary.swift"), 2)


if __name__ == "__main__":
    unittest.main()
