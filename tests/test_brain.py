"""Brain contract: session context, explicit durable notes, remote consent and limits."""
import json
import os
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from jarvis.brain import BrainError, BrainProviderError, JarvisBrain, brain_ready
from jarvis.engine import JarvisEngine
from jarvis.server import make_server
from jarvis.storage import MemoryStore


class BrainTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "memory.sqlite3"
        self.store = MemoryStore(self.path)
        self.brain = JarvisBrain(self.store, JarvisEngine(self.store))

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_short_context_without_persistent_transcript(self):
        first = self.brain.handle("오늘은 개발 이야기를 하고 싶어")
        self.assertEqual(first["action"], "chat_unavailable")
        second = self.brain.handle("방금 내가 뭐라고 했지?", conversation_id=first["conversation_id"])
        self.assertIn("오늘은 개발 이야기를", second["text"])
        self.assertEqual(second["conversation_id"], first["conversation_id"])
        self.assertEqual(self.store.count_memories(), 0)
        self.assertNotIn("오늘은 개발 이야기를", json.dumps(self.store.recent_activity(), ensure_ascii=False))
        self.store.close()
        reopened = MemoryStore(self.path)
        try:
            self.assertEqual(reopened.count_memories(), 0)
            # No session history is persisted to SQLite.
            self.assertEqual(len(JarvisBrain(reopened, JarvisEngine(reopened)).sessions), 0)
        finally:
            reopened.close()
        # Avoid double close in tearDown after intentional reopen.
        self.store = MemoryStore(self.path)

    def test_explicit_notes_search_and_reset_keeps_saved_memory(self):
        msg = self.brain.handle("기억해: 위키 프로젝트 배포 먼저")
        session = msg["conversation_id"]
        self.assertEqual(self.store.count_memories(), 1)
        found = self.brain.handle("기억 검색: 배포", conversation_id=session)
        self.assertEqual(found["action"], "memory_search")
        self.assertIn("위키 프로젝트 배포", found["text"])
        cleared = self.brain.handle("대화 초기화", conversation_id=session)
        self.assertEqual(cleared["action"], "chat_reset")
        self.assertEqual(self.store.count_memories(), 1)
        next_msg = self.brain.handle("방금 내가 뭐라고 했지?", conversation_id=session)
        self.assertIn("앞선 질문이 없습니다", next_msg["text"])

    def test_context_is_scoped_to_random_session(self):
        a = self.brain.handle("내 프로젝트는 위키야")
        b = self.brain.handle("방금 내가 뭐라고 했지?", conversation_id="made-up-id")
        self.assertNotEqual(a["conversation_id"], b["conversation_id"])
        self.assertIn("앞선 질문이 없습니다", b["text"])

    def test_existing_actions_keep_contract(self):
        open_ = self.brain.handle("자비스, 대시보드 열어")
        self.assertEqual(open_["action"], "open_dashboard")
        self.assertEqual(open_["mode"], "dashboard")
        closed = self.brain.handle("자비스 대시보드 닫아", conversation_id=open_["conversation_id"])
        self.assertEqual(closed["action"], "close_workspace")
        self.assertEqual(closed["mode"], "orb")

    def test_project_status_does_not_claim_live_github_access(self):
        answer = self.brain.handle("우리 프로젝트 상태 알려줘")
        self.assertEqual(answer["action"], "project_overview")
        self.assertEqual(answer["mode"], "projects")
        self.assertIn("GitHub", answer["text"])
        self.assertIn("아직", answer["text"])

    def test_named_project_status_uses_saved_evidence_without_new_network(self):
        wiki = self.store.create_project(
            "DECHIVE.WIKI", "영어 기반 지식 아카이브 배포",
            "Aprasaks/dechive-wiki")
        task = self.store.add_project_task(wiki["id"], "실제 공개 확인")
        self.store.update_project_task(wiki["id"], task["id"], "doing")
        self.store.save_project_check(wiki["id"], {
            "repository": "Aprasaks/dechive-wiki",
            "branch": "main",
            "head_sha": "a" * 40,
            "workflow_state": "unavailable",
            "workflow_conclusion": "unknown",
            "workflow_url": "",
        })
        with patch("jarvis.tools.verify_public_github") as network:
            r = self.brain.handle("DECHIVE.WIKI 지금 어디까지 진행됐어?")
            spaced = self.brain.handle("dechive wiki 현재 상태 알려줘")
        self.assertEqual(r["action"], "project_named_overview")
        self.assertEqual(r["mode"], "projects")
        self.assertFalse(r["executed"])
        self.assertIn("실제 공개 확인 (진행)", r["text"])
        self.assertIn("커밋 aaaaaaaaaa", r["text"])
        self.assertIn("실제 AWS 배포", r["text"])
        self.assertEqual(spaced["action"], "project_named_overview")
        network.assert_not_called()

    def test_named_project_next_actions_are_saved_user_tasks(self):
        wiki = self.store.create_project(
            "DECHIVE.WIKI", "영어 지식 아카이브", "Aprasaks/dechive-wiki")
        started = self.store.add_project_task(wiki["id"], "관리자 페이지 연결")
        self.store.update_project_task(wiki["id"], started["id"], "doing")
        self.store.add_project_task(wiki["id"], "배포 도메인 확인")
        blocked = self.store.add_project_task(wiki["id"], "AWS 접근 권한 해결")
        self.store.update_project_task(wiki["id"], blocked["id"], "blocked")
        with patch("jarvis.tools.verify_public_github") as network:
            reply = self.brain.handle("DECHIVE.WIKI 다음 뭐해야 해?")
        self.assertEqual(reply["action"], "project_named_overview")
        self.assertIn("다음 이어 할 일(사용자 기록)", reply["text"])
        self.assertLess(
            reply["text"].index("관리자 페이지 연결 (진행)"),
            reply["text"].rindex("배포 도메인 확인 (예정)")
        )
        self.assertIn("막힌 작업(사용자 기록)", reply["text"])
        self.assertIn("AWS 접근 권한 해결", reply["text"])
        self.assertFalse(reply["executed"])
        network.assert_not_called()

    def test_self_addressed_status_reads_only_exact_jarvis_project(self):
        project = self.store.create_project(
            "JARVIS eidis", "Mac 개인 AI", "Aprasaks/eidis")
        self.store.add_project_task(project["id"], "오래된 예정 작업")
        recent = self.store.add_project_task(project["id"], "실제 음성 명령 화면 확인")
        self.store.update_project_task(project["id"], recent["id"], "doing")
        self.store.add_project_task(project["id"], "새로운 미검증 권한 확인")
        with patch("jarvis.tools.verify_public_github") as network:
            answer = self.brain.handle("자비스, 다음 할 일 뭐야?")
            alias = self.brain.handle("Jarvis 지금 어디까지 했어?")
        for reply in (answer, alias):
            self.assertEqual(reply["action"], "project_self_overview")
            self.assertFalse(reply["executed"])
            self.assertEqual(reply["brain_source"], "local")
            self.assertIn("자비스 자신의 프로젝트 기록", reply["text"])
            self.assertIn("실제 음성 명령 화면 확인 (진행)", reply["text"])
            self.assertIn("새로운 미검증 권한 확인 (예정)", reply["text"])
            self.assertIn("실제 코드 실행·테스트·배포 상태", reply["text"])
            self.assertNotIn("GitHub 공개 API를 지금 직접 조회", reply["text"])
            self.assertLess(len(reply["spoken"]), 600)
        network.assert_not_called()

    def test_self_alias_never_overrides_explicit_wiki_or_global_request(self):
        self.store.create_project("JARVIS eidis", "Mac AI", "Aprasaks/eidis")
        wiki = self.store.create_project("DECHIVE.WIKI", "위키", "Aprasaks/dechive-wiki")
        self.store.add_project_task(wiki["id"], "위키 공개 배포 확인")
        wiki_answer = self.brain.handle("자비스, DECHIVE.WIKI 다음 해야 할 일은?")
        self.assertEqual(wiki_answer["action"], "project_named_overview")
        self.assertIn("위키 공개 배포 확인", wiki_answer["text"])
        self.assertNotIn("자비스 자신의 프로젝트 기록", wiki_answer["text"])
        overview = self.brain.handle("자비스, 프로젝트 현황 알려줘")
        self.assertEqual(overview["action"], "project_overview")
        unknown = self.brain.handle("자비스, 모르는서비스 다음 할 일 뭐야?")
        self.assertNotEqual(unknown["action"], "project_self_overview")

    def test_no_self_project_is_not_fabricated(self):
        self.store.create_project("DECHIVE.WIKI", "위키", "Aprasaks/dechive-wiki")
        answer = self.brain.handle("자비스, 다음 할 일 뭐야?")
        self.assertNotEqual(answer["action"], "project_self_overview")
        answer_without_prefix = self.brain.handle("다음 할 일 뭐야?")
        self.assertNotEqual(answer_without_prefix["action"], "project_self_overview")

    def test_unmatched_project_word_does_not_invent_status(self):
        r = self.brain.handle("모르는서비스 지금 어디까지 진행됐어?")
        self.assertNotEqual(r["action"], "project_named_overview")

    def test_remote_is_disabled_until_three_separate_conditions(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "", "JARVIS_BRAIN_MODEL": "",
                                     "JARVIS_ENABLE_BRAIN_API": "0"}):
            self.assertFalse(brain_ready())
            local = self.brain.handle("전문가처럼 설명해줘")
            self.assertEqual(local["action"], "chat_unavailable")
            with self.assertRaises(BrainError):
                self.brain.handle("왜 프로젝트가 실패할까?", remote_consent=True)
        self.assertEqual(self.brain.remote_calls, 0)

    def test_mock_remote_sends_context_and_only_relevant_notes(self):
        saved = self.brain.handle("기억해: 자비스 화면은 검은 은하처럼")
        session = saved["conversation_id"]
        self.brain.handle("그럼 인터페이스는 어떻게?", conversation_id=session)
        fake = json.dumps({
            "output": [{"type":"message","content":[{"type":"output_text",
                       "text":"검은 은하 배경은 유지하고 정보는 접어두는 게 좋아요."}]}]
        }, ensure_ascii=False).encode()

        class FakeResponse:
            def __enter__(self): return self
            def __exit__(self,*_): return False
            def read(self, _): return fake

        def fake_http(req, timeout):
            self.assertEqual(req.full_url, "https://api.openai.com/v1/responses")
            self.assertEqual(req.get_header("Authorization"), "Bearer test-key")
            body = json.loads(req.data)
            self.assertFalse(body["store"])
            self.assertNotIn("tools", body)
            self.assertEqual(body["input"][-1]["content"], "검은 은하 느낌이 어때?")
            self.assertTrue(any("검은 은하" in str(m) for m in body["input"]))
            return FakeResponse()

        with patch.dict(os.environ, {"OPENAI_API_KEY":"test-key",
                                     "JARVIS_BRAIN_MODEL":"gpt-6-astra",
                                     "JARVIS_ENABLE_BRAIN_API":"1"}), \
             patch("jarvis.brain.urlopen", side_effect=fake_http):
            reply = self.brain.handle("검은 은하 느낌이 어때?", conversation_id=session,
                                      remote_consent=True)
        self.assertEqual(reply["action"], "chat_reply")
        self.assertEqual(reply["brain_source"], "ai")
        self.assertEqual(self.brain.remote_calls, 1)
        self.assertIn("정보는 접어", reply["text"])
        self.assertNotIn("검은 은하 느낌이 어때?", json.dumps(self.store.recent_activity(), ensure_ascii=False))

    def test_bounded_provider_attempts_no_unapproved_retry(self):
        fake = b'{"output":[{"type":"message","content":[{"type":"output_text","text":"mock"}]}]}'
        class FakeResponse:
            def __enter__(self): return self
            def __exit__(self,*_): return False
            def read(self,_):return fake
        with patch.dict(os.environ, {"OPENAI_API_KEY":"test","JARVIS_BRAIN_MODEL":"gpt-6-astra",
                                     "JARVIS_ENABLE_BRAIN_API":"1"}), \
             patch("jarvis.brain.urlopen",return_value=FakeResponse()) as http:
            for _ in range(3):
                answer = self.brain.handle("아무 말이나 답해줘",remote_consent=True)
                self.assertEqual(answer["brain_source"],"ai")
            with self.assertRaises(BrainError):
                self.brain.handle("다시 알려줘",remote_consent=True)
        self.assertEqual(http.call_count,3)

    def test_sql_like_wildcards_are_literal(self):
        self.store.add_memory("중요한 프로젝트_한글")
        self.store.add_memory("프로젝트X한글")
        matches = self.store.search_memories("프로젝트_한글")
        self.assertEqual(len(matches),1)
        self.assertIn("_",matches[0]["content"])

    def test_api_chat_origin_session_and_zero_cost_default(self):
        httpd = make_server(port=0, db_path=Path(self.tmp.name)/"api.sqlite3")
        thread=threading.Thread(target=httpd.serve_forever,daemon=True)
        thread.start()
        base=f"http://127.0.0.1:{httpd.server_port}"
        def post(text, conversation_id=None, origin=None):
            data=json.dumps({"text":text,"conversation_id":conversation_id,
                             "remote_consent":False}, ensure_ascii=False).encode()
            req=Request(base+"/api/chat",data=data,method="POST",
                        headers={"Content-Type":"application/json","Origin": origin or base})
            return urlopen(req)
        try:
            with urlopen(base+"/api/status") as response:
                status=json.load(response)
            self.assertFalse(status["brain"]["remote_configured"])
            with post("프로젝트 시작") as r:
                first=json.load(r)
            with post("방금 내가 뭐라고 했지?",first["conversation_id"]) as r:
                second=json.load(r)
            self.assertIn("프로젝트 시작",second["text"])
            self.assertEqual(first["conversation_id"],second["conversation_id"])
            with self.assertRaises(HTTPError) as cm:
                post("안녕",origin="https://malicious.example")
            self.assertEqual(cm.exception.code,403)
            with urlopen(base+"/api/activity") as response:
                activity=json.load(response)
            self.assertNotIn("프로젝트 시작",json.dumps(activity,ensure_ascii=False))
            with urlopen(base+"/api/memories") as response:
                self.assertEqual(json.load(response)["items"],[])
        finally:
            httpd.shutdown()
            httpd.server_close()
            httpd.RequestHandlerClass.store.close()
            thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
