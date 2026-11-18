"""Read-only handoff view must separate user notes, local Git and public GitHub."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "macos/Sources/EidisMac/JarvisHandoffReport.swift"
PANEL = ROOT / "macos/Sources/EidisMac/ApprovedProjectsPanel.swift"


class HandoffReportContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = REPORT.read_text(encoding="utf-8")
        cls.panel = PANEL.read_text(encoding="utf-8")

    def test_handoff_never_fetches_data_or_changes_files(self):
        self.assertIn("struct JarvisHandoffReport", self.report)
        self.assertIn("static func make(project: WorkProject", self.report)
        for forbidden in ("URLSession", "Process()", "FileManager.default",
                          "NSPasteboard", "git push", "URLRequest",
                          "UserDefaults", "AXUIElementPerformAction"):
            self.assertNotIn(forbidden, self.report)

    def test_sources_and_dates_are_labeled(self):
        for phrase in (
            "작업 현황 · 사용자가 기록한 상태",
            "Mac 로컬 Git · 명시적 수동 확인 결과",
            "공개 GitHub · 마지막 승인 조회 기록",
            "현재 시점 재검사 아님",
            "AWS 배포·사이트 공개·테스트 성공·작업 완료 여부",
            "Mac 폴더가 해당 GitHub 저장소와 동일한지 자동 검증하지 않음",
        ):
            self.assertIn(phrase, self.report)
        self.assertNotIn("snapshot.rootPath", self.report)
        self.assertIn("project.nextTasks", self.report)
        self.assertIn("project.blockedTasks", self.report)

    def test_copy_is_only_explicit_user_action(self):
        self.assertIn('Button("인수인계 내용 복사")', self.panel)
        self.assertIn("NSPasteboard.general.setString(summary.body", self.panel)
        self.assertIn("JarvisHandoffReport.make(", self.panel)
        self.assertIn("localEvidence: work.localEvidence[selected.id]", self.panel)
        self.assertIn("조회 기록은 작성 당시의 스냅샷입니다", self.panel)


if __name__ == "__main__":
    unittest.main()
