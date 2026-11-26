"""Regression: ordinary JARVIS chat must use local projects without invented access denials."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
PROJECT = (ROOT / "macos/Sources/EidisMac/JarvisCasualProjectKnowledge.swift").read_text()


class CasualProjectRecallContract(unittest.TestCase):
    def test_real_local_project_list_is_read_only_and_complete_as_registered(self):
        self.assertIn('http://127.0.0.1:8765/api/projects', PROJECT)
        self.assertIn('request.httpMethod = "GET"', PROJECT)
        self.assertIn("let result = try JSONDecoder().decode(ProjectList.self", PROJECT)
        self.assertIn("return .available(Array(result.items.prefix(30)))", PROJECT)
        self.assertIn("static func inventoryReply(for result: Result)", PROJECT)
        self.assertIn("로컬 기록에 등록된 프로젝트", PROJECT)
        self.assertIn("실제로 진행 중인 모든 프로젝트", PROJECT)
        self.assertIn("목록 조회를 시도했지만 지금은 데이터를 읽지 못했어요", PROJECT)
        self.assertNotIn('request.httpMethod = "POST"', PROJECT)

    def test_chat_looks_up_projects_before_answering_inventory(self):
        self.assertIn(
            "let projectRecords = await JarvisCasualProjectKnowledge.lookup(prompt, session: session)",
            CHAT,
        )
        self.assertIn("JarvisCasualProjectKnowledge.isInventoryQuestion(prompt)", CHAT)
        self.assertIn("JarvisCasualProjectKnowledge.inventoryReply(for: projectRecords)", CHAT)
        self.assertIn("JarvisCasualProjectKnowledge.referenceContext(for: projectRecords)", CHAT)
        self.assertIn('(projectContext.isEmpty ? "" : "\\n" + projectContext)', CHAT)
        self.assertIn('conversation.append(["role": "assistant", "content": inventory])', CHAT)

    def test_personal_call_and_correction_are_handled_without_lecture(self):
        self.assertIn('["자비스", "자비스야"].contains(wake)', CHAT)
        self.assertIn("네, 오빠. 듣고 있어요.", CHAT)
        self.assertIn("사용자가 방금 정정한 말은 앞선 당신의 추정이나 오해보다 우선합니다", CHAT)
        self.assertIn("줄였다'는 말은 감소로 이해", CHAT)
        self.assertIn("수치가 앞뒤로 맞지 않는다면 추측하지 말고 짧게 확인", CHAT)


if __name__ == "__main__":
    unittest.main()
