"""Local Git checks are user-triggered, read-only and kept off the server."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
GIT = ROOT / "macos/Sources/EidisMac/LocalGitInspector.swift"
WORK = ROOT / "macos/Sources/EidisMac/ApprovedProjectsPanel.swift"


class LocalGitContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.git = GIT.read_text(encoding="utf-8")
        cls.work = WORK.read_text(encoding="utf-8")

    def test_only_fixed_git_read_commands(self):
        for command in (
            '"rev-parse", "--show-toplevel"',
            '"rev-parse", "--abbrev-ref", "HEAD"',
            '"rev-parse", "--verify", "HEAD"',
            '"status", "--porcelain=v1", "-z"',
            '"--no-optional-locks"',
            '"core.fsmonitor=false"',
        ):
            self.assertIn(command, self.git)
        for excluded in (
            '"push"', '"pull"', '"fetch"', '"commit"', '"reset"', '"checkout"',
            '"clean"', '"add"', '"merge"', '"rebase"', '"switch"', '"clone"',
            'URLSession', 'shell -c', '/bin/zsh', '/bin/bash',
        ):
            self.assertNotIn(excluded, self.git)

    def test_explicit_folder_picker_and_no_automatic_inspection(self):
        self.assertIn("NSOpenPanel()", self.work)
        self.assertIn('Button("현재 코드 상태 한 번 확인")', self.work)
        self.assertIn('Button("연결 해제")', self.work)
        self.assertIn("Task { await work.connectLocalFolder", self.work)
        self.assertIn("Task { await work.inspectLocalFolder", self.work)
        self.assertIn("UserDefaults.standard.set(evidence.rootPath", self.work)
        self.assertIn("UserDefaults.standard.removeObject", self.work)
        self.assertIn("private func localFolderKey(", self.work)
        self.assertIn("localEvidence.removeValue(forKey: projectId)", self.work)
        self.assertIn("Task.detached(priority: .userInitiated)", self.work)
        startup = self.work.split("func refresh() async {", 1)[1].split(
            "func addTask", 1
        )[0]
        self.assertNotIn("LocalGitInspector.inspect", startup)

    def test_only_summary_counts_are_displayed(self):
        self.assertIn("changedTrackedEntries", self.work)
        self.assertIn("untrackedEntries", self.work)
        self.assertIn("headSHA.prefix(12)", self.work)
        self.assertIn("checkedAt.formatted", self.work)
        self.assertIn("GitHub 원격 기록과 Mac 로컬 코드는 서로 다를 수 있습니다", self.work)
        self.assertIn("outputLimit = 524_288", self.git)
        self.assertIn("read(upToCount: 8192)", self.git)
        self.assertIn("Date()", self.git)
        self.assertNotIn("git log", self.git)
        self.assertNotIn("FileManager.default.contentsOfDirectory", self.git)


if __name__ == "__main__":
    unittest.main()
