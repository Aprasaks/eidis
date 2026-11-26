from pathlib import Path
import json, unittest
ROOT=Path(__file__).resolve().parents[1]
S=ROOT/'macos/Sources/EidisMac'
C=(S/'JarvisKnowledgeCatalog.swift').read_text()
W=(S/'JarvisProjectWorkspace.swift').read_text()
A=(S/'JarvisAgentTerminalBay.swift').read_text()

class KnowledgeCatalog(unittest.TestCase):
    def test_original_catalog_order(self):
        doc=json.loads((ROOT/'docs/knowledge/knowledge-catalog.json').read_text())
        topics=doc['topics']
        self.assertEqual([t['number'] for t in topics],list(range(1,570)))
        self.assertEqual(len({t['code'] for t in topics}),569)
        self.assertEqual(len({t['category'] for t in topics}),24)
        self.assertEqual(topics[36]['code'],'K03-06')
        self.assertEqual(topics[37]['code'],'K03-07')
        self.assertEqual(topics[38]['code'],'K03-08')
        self.assertEqual(doc['continuationCode'],'K03-06')
    def test_view_uses_real_status_and_scroll(self):
        self.assertNotIn('집필 순서 원본 열기',W)
        self.assertIn('ForEach(topics)',W)
        self.assertIn('LazyVStack',W)
        self.assertIn('knowledgeCatalog.publicArticles?.count',W)
        self.assertIn('status==\\"published\\" && humanVerified==true',C)
        self.assertIn('staged.contains(active.code) ? "검토 등록 기록 · 미공개"',W)
        self.assertIn('nextCandidate(afterStaged:',W)
    def test_daily_gate_before_launch(self):
        self.assertIn('static let limit = 3',C)
        self.assertIn('O_EXCL',C)
        self.assertIn('Asia/Seoul',C)
        self.assertLess(A.index('JarvisKnowledgeDailyBudget.reserve()'),A.index('knowledgePilot = JarvisKnowledgePilotRun(id: runID'))
        self.assertIn('agentBay.knowledgeDailyLimitReached',W)
if __name__=='__main__':unittest.main()
