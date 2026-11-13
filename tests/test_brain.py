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
        self.assertEqual(answer["action"], "chat_local_status")
        self.assertIn("GitHub", answer["text"])
        self.assertIn("아직", answer["text"])

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
