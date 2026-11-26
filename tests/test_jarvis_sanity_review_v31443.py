from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
A=(ROOT/'macos/Sources/EidisMac/JarvisAgentTerminalBay.swift').read_text()
W=(ROOT/'macos/Sources/EidisMac/JarvisProjectWorkspace.swift').read_text()
class SanityReview(unittest.TestCase):
    def test_explicit_opt_in_and_ready_gate(self):
        self.assertIn('@Published var stageAfterPilot = false',A)
        self.assertIn('stageAfterPilotID = topic == nil && stageAfterPilot ? runID : nil',A)
        self.assertIn('if shouldStage && run.state == .artifactsReady',A)
        self.assertIn('guard canStageKnowledge',A)
        self.assertIn('run.hasPassingImageReview()',A)
        self.assertIn('agentBay.stageKnowledgePilot()',W)
    def test_no_publication_and_real_receipt(self):
        self.assertIn('receipt.status == "review", !receipt.humanVerified',A)
        self.assertIn('!aborted && code == 0 && run.sanityReceipt() != nil',A)
        self.assertIn('"--mode", "stage"',A)
        self.assertIn('마지막 등록 기록',W)
if __name__=='__main__':unittest.main()
