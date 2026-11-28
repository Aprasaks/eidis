"""Known local dashboard abilities should be actionable without magic wording."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
LIVE=(ROOT/'macos/Sources/EidisMac/JarvisLiveDashboard.swift').read_text()
CHAT=(ROOT/'macos/Sources/EidisMac/JarvisOverlayConversation.swift').read_text()

class VerifiedDashboardIntentMapping(unittest.TestCase):
    def test_named_local_panels_support_colloquial_opening_phrases(self):
        self.assertIn('let localProjectList = ["내프로젝트"', LIVE)
        self.assertIn('"프로젝트목록", "프로젝트를", "프로젝트열어"', LIVE)
        self.assertIn('let localArchive = ["내보관함"', LIVE)
        self.assertIn('"저장한자료", "내지식", "지식보관함"', LIVE)
        self.assertIn('if localProjectList { return .show(.projects) }',LIVE)
        self.assertIn('if localArchive { return .show(.knowledge) }',LIVE)

    def test_project_files_not_mistaken_for_internal_dashboard(self):
        self.assertIn('let fileRequest = ["파일", "폴더"',LIVE)
        self.assertIn('let canceledRequest = ["열지마"',LIVE)
        self.assertIn('if opening && !fileRequest && !canceledRequest {',LIVE)
        self.assertIn('return .unavailable',LIVE)

    def test_casual_chat_opens_explicit_panel_before_inventory_response(self):
        router=CHAT.split('private func shouldRouteCasualToWorkspace(',1)[1].split('private func respondCasually(',1)[0]
        self.assertIn('let explicitlyOpen = ["열어", "띄워", "켜줘", "실행해"]',router)
        self.assertIn('if explicitlyOpen, let intent = JarvisLiveDashboardIntent.parse(phrase)',router)
        self.assertLess(router.index('if explicitlyOpen,'),router.index('if JarvisCasualProjectKnowledge.isInventoryQuestion(phrase)'))
        self.assertIn('response = try await planAndRespond(command, token: token)',CHAT)

    def test_no_false_claims_about_nonexistent_integrations(self):
        self.assertIn('그 화면의 데이터 연결은 아직 없어요',CHAT)
        self.assertIn('그 작업을 실행하는 기능은 아직 없어요',CHAT)
        self.assertIn('JarvisLiveDashboardIntent.parse(prompt)',CHAT)
        self.assertIn('outcome = await liveDashboard.show(mode)',CHAT)
        self.assertIn('await self.stockBoard.open(intent)',CHAT)
        self.assertIn('Self.notYetConnectedResponse(for: prompt)',CHAT)

if __name__=='__main__':unittest.main()
