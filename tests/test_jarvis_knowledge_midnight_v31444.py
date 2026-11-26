from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
S=ROOT/'macos/Sources/EidisMac'
M=(S/'JarvisLiveDashboard.swift').read_text()
V=(S/'JarvisCommandCenterView.swift').read_text()
P=(S/'JarvisKnowledgeMidnightNavigation.swift').read_text()

class MidnightNavigation(unittest.TestCase):
    def test_kst_daily_once(self):
        self.assertIn('TimeZone(identifier: "Asia/Seoul")',P)
        self.assertIn('parts.hour == 0, parts.minute == 0',P)
        self.assertIn('lastOpenedDay != dayKey',P)
        self.assertIn('defaults.set(day, forKey: key)',M)
    def test_navigation_only(self):
        section=M.split('func openKnowledgeAtMidnightIfDue',1)[1].split('func hide()',1)[0]
        self.assertIn('workroomProject = .dev',section)
        self.assertIn('isVisible && mode == .overview',section)
        self.assertIn('workroomProject != nil',section)
        self.assertNotIn('runKnowledgePilot',section)
        self.assertNotIn('stageKnowledgePilot',section)
        self.assertIn('model.openKnowledgeAtMidnightIfDue()',V)
if __name__=='__main__':unittest.main()
