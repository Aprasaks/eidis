"""Native guarded note revision contract and audit boundaries."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORK = (ROOT / "macos/Sources/EidisMac/ApprovedProjectsPanel.swift").read_text("utf-8")
REVISION = (ROOT / "macos/Sources/EidisMac/JarvisNoteRevision.swift").read_text("utf-8")
WRITER = (ROOT / "macos/Sources/EidisMac/JarvisTaskNote.swift").read_text("utf-8")
CI = (ROOT / ".github/workflows/ci.yml").read_text("utf-8")


class NoteRevisionContractTests(unittest.TestCase):
    def test_preview_and_explicit_new_file_approval(self):
        for phrase in ('Button("이 메모 수정본 작성")',
                       'Button("수정본 전체 미리보기")',
                       'Button("새 수정본 저장 승인 화면")',
                       'Button("승인하고 수정본 새 파일 저장")',
                       'Button("취소", role: .cancel) { revisionProposal = nil }',
                       'JarvisNoteRevision.prepare(',
                       'work.saveApprovedRevision(proposal)'):
            self.assertIn(phrase, WORK)

    def test_fresh_project_lookup_and_no_automatic_actions(self):
        source = WORK.split("func saveApprovedRevision(", 1)[1].split(
            "func readSavedNote(", 1)[0]
        self.assertIn('fetch("/api/projects")', source)
        self.assertIn("$0.repoFullName == proposal.repository", source)
        self.assertIn("localFolder(projectId: proposal.projectId)", source)
        self.assertIn("JarvisNoteRevision.save(", source)
        self.assertIn("자동 재시도하지 않습니다", source)
        for forbidden in ("NSWorkspace.shared.open", "/api/projects/status",
                          "git push", "git commit", "Process()"):
            self.assertNotIn(forbidden, source)

    def test_original_preserved_and_stale_source_rejected(self):
        for required in ("originalFilename", "originalText", "revisedText",
                         "current == proposal.originalText",
                         "JarvisNoteLibrary.read(",
                         "JarvisTaskNote.prepareRevision(",
                         "JarvisTaskNote.save(",
                         "case originalChanged", "(0...120).contains(age)",
                         "task.status == \"doing\" || task.status == \"todo\""):
            self.assertIn(required, REVISION)
        self.assertIn("contentOverride: markdown", WRITER)
        self.assertIn("O_EXCL", WRITER)
        self.assertIn("O_NOFOLLOW", WRITER)
        self.assertIn("actual == bytes", WRITER)
        self.assertIn("fsync(file)", WRITER)
        for forbidden in ("URLSession(", "Process()", "NSWorkspace.shared.open",
                          "git push", "git commit", "renameat("):
            self.assertNotIn(forbidden, REVISION)

    def test_native_ci_compiles_revisions(self):
        self.assertEqual(CI.count("macos/Sources/EidisMac/JarvisNoteRevision.swift"), 2)


if __name__ == "__main__":
    unittest.main()
