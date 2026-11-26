import unittest
from pathlib import Path
A=(Path(__file__).resolve().parents[1]/"macos/Sources/EidisMac/JarvisAgentTerminalBay.swift").read_text()
class RepairContracts(unittest.TestCase):
    def test_preserve_original_and_budget(self):
        block=A.split("private func repairKnowledgePilot(")[1].split("private var repairProtectedDigests")[0]
        self.assertIn("fm.copyItem(at: source.directory",block)
        self.assertIn("JarvisKnowledgeDailyBudget.reserveRepair(topicCode: topic.code)",block)
        self.assertIn("repairProtectedDigests[id] = protected",block)
        self.assertIn('"article.md","cover.png","job.json","body-01.png"',block)
        self.assertIn('name == "body-01.png" ? Self.repairDigest(data) != digest',A)
        self.assertIn("run.hasPassingImageReview() && repairPreserved",A)
        self.assertNotIn('"--mode", "publish"',A)
    def test_recovery_is_explicit_once_and_deadline_bounded(self):
        self.assertIn('approval["reason"] == "owner-requested-image-repair"',A)
        self.assertIn('summary["reason"] == "제작 미완료 · 다음 근무에서 재검토"',A)
        self.assertIn('"recovery.lock"',A)
        self.assertIn("O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW",A)
        self.assertIn('"summary-before-recovery.json"',A)
        self.assertIn("recoveryTopic == nil || recoveryTopic == topic.code",A)
        self.assertIn("await waitForNightWorker(deadline: deadline)",A)
        self.assertIn("!knowledgeDailyLimitReached",A)
if __name__=="__main__": unittest.main()
