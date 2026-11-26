from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
S=R/'macos/Sources/EidisMac'
A=(S/'JarvisAgentTerminalBay.swift').read_text()
P=(S/'JarvisKnowledgeNightPolicy.swift').read_text()
V=(S/'JarvisCommandCenterView.swift').read_text()
W=(S/'JarvisProjectWorkspace.swift').read_text()
class KnowledgeNight(unittest.TestCase):
    def test_clock_and_daily_claim(self):
        self.assertIn('Asia/Seoul',P)
        self.assertIn('O_EXCL',P)
        self.assertIn('calendar.component(.hour, from: date) == 0',P)
        self.assertIn('deadline.timeIntervalSince(now) >= 300',P)
        self.assertIn('self.beginNightShiftIfDue()',A)
        self.assertNotIn('agentBay.beginNightShiftIfDue()',V)
        self.assertIn('JarvisAgentTerminalBay.shared.startNightScheduler()', (S/'JarvisBundledServer.swift').read_text())
        self.assertIn('let agentBay = JarvisAgentTerminalBay.shared', (S/'JarvisOverlayConversation.swift').read_text())
        self.assertIn('agentBay.nightShiftFinishedDay',V)
    def test_inventory_and_bounded_loop(self):
        self.assertIn('documents.allSatisfy',P)
        self.assertIn('!occupied.contains($0.resolvedSlug)',P)
        self.assertIn('attempted.count < JarvisKnowledgeDailyBudget.limit',A)
        self.assertIn('inventory.next(in: catalog)',A)
        self.assertIn('topic: topic',A)
        self.assertIn('reusableNightPackage(for: topic)',A)
        self.assertIn('knowledgePilot?.sanityReceipt()?.slug == topic.resolvedSlug',A)
        self.assertIn('nightStopRequested = true',A)
    def test_unpublished_only(self):
        self.assertIn('general-reference',A)
        self.assertIn('job.json',A)
        self.assertIn('실제 공개 금지',A)
        self.assertIn('"--mode", "stage"',A)
        self.assertNotIn('"--mode", "publish"',A)
        self.assertIn('stageAfterPilotID = topic == nil && stageAfterPilot ? runID : nil',A)
        self.assertIn('agentBay.nightShiftStatus',W)
if __name__=='__main__':unittest.main()
