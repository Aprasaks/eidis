from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
S=ROOT/'macos/Sources/EidisMac'
M=(S/'JarvisKnowledgeRunMaintenance.swift').read_text()
A=(S/'JarvisAgentTerminalBay.swift').read_text()
class KnowledgeMaintenance(unittest.TestCase):
    def test_explicit_disposable_allowlist(self):
        self.assertIn('[".swift-module-cache", ".DS_Store"]',M)
        self.assertIn('["pcm", "swiftmodule", "timestamp"]',M)
        self.assertIn('v.isSymbolicLink != true',M)
        self.assertIn('run.deletingLastPathComponent().path == root.path',M)
        self.assertNotIn('removeItem(at: run)',M)
    def test_successful_exit_only_and_before_stage(self):
        part=A.split('private func finishKnowledgePilot(',1)[1].split('private var processes:',1)[0]
        self.assertIn('if !aborted && code == 0 {',part)
        self.assertIn('JarvisKnowledgeRunMaintenance.clean(',part)
        self.assertLess(part.index('JarvisKnowledgeRunMaintenance.clean('),part.index('let shouldStage'))
        self.assertIn('임시 캐시 정리 보류',part)
if __name__=='__main__':unittest.main()
