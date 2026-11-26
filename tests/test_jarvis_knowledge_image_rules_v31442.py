from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
AGENT = (ROOT/'macos/Sources/EidisMac/JarvisAgentTerminalBay.swift').read_text()
WORK = (ROOT/'macos/Sources/EidisMac/JarvisProjectWorkspace.swift').read_text()
COVER = (ROOT/'docs/knowledge/KNOWLEDGE_IMAGE_RULES.md').read_text()
BODY = (ROOT/'docs/knowledge/KNOWLEDGE_BODY_IMAGE_RULES.md').read_text()
class KnowledgeImageRules(unittest.TestCase):
    def test_exact_cover_copy_and_required_read(self):
        for phrase in ('DECHIVE KNOWLEDGE','데이터 증강이란?','같은 데이터를 다르게 보다','하나의 데이터로 어떻게 더 많이 배울까?','필기체'):
            self.assertIn(phrase,COVER)
            self.assertIn(phrase,AGENT)
        for name in ('KNOWLEDGE_IMAGE_RULES.md','KNOWLEDGE_BODY_IMAGE_RULES.md','pilot-draft.md'):
            self.assertIn('reference/'+name,AGENT)
            self.assertIn('"'+name+'"',AGENT)
    def test_independent_evaluation_and_visual_review(self):
        self.assertIn('먼저 원본 데이터 집합을 학습용과 평가용으로 분할',BODY)
        self.assertIn('동일 원본이나 그 변형이 양쪽에 들어간 것처럼 보이지 않게',BODY)
        self.assertIn('실제 이미지 보기 도구로 열어 검사',AGENT)
    def test_file_presence_not_enough(self):
        self.assertIn('filesComplete && run.hasPassingImageReview()',AGENT)
        self.assertIn('reviewPassed ? .artifactsReady : .incomplete',AGENT)
        self.assertIn('lines.filter { $0.hasPrefix(prefix) } == [expected]',AGENT)
        self.assertIn('이미지 자체 검수 PASS · 직접 확인 대기',WORK)
        self.assertIn('실제 공개 금지',AGENT)
if __name__=='__main__':unittest.main()
