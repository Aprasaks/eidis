"""JARVIS learning loop: opt-in, user review, safe retrieval, correction/erasure."""
import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from jarvis.storage import MemoryStore
from jarvis.thinking import related_context
from jarvis.server import make_server
from jarvis import learning


class LocalLearningTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "jarvis.sqlite3"
        self.store = MemoryStore(self.path)

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_learning_is_off_until_explicit_opt_in(self):
        self.assertFalse(learning.enabled(self.store))
        self.assertEqual(learning.summary(self.store)["pending"], [])
        with self.assertRaises(ValueError):
            learning.propose(self.store, "working_style", "블로그 작성 시 원문을 검증한다",
                             "나는 블로그 작성 시 원문을 검증한다")
        self.assertEqual(learning.summary(self.store)["pending_count"], 0)
        with self.assertRaises(ValueError):
            learning.set_enabled(self.store, "true")

    def test_candidate_approved_retrieved_after_restart(self):
        self.store.upsert_profile("values", "검증부터 시작한다")
        old = self.store.add_memory("기존 자료는 그대로 남긴다")
        learning.set_enabled(self.store, True)
        first = learning.propose(self.store, "working_style",
            "블로그 글을 쓸 때 근거를 먼저 검증한다",
            "나는 블로그 글을 쓸 때 근거를 먼저 검증하고 싶어.")
        again = learning.propose(self.store, "working_style",
            "블로그 글을 쓸 때 근거를 먼저 검증한다",
            "나는 블로그 글을 쓸 때 근거를 먼저 검증하고 싶어.")
        self.assertEqual(first["id"], again["id"])
        self.assertEqual(first["status"], "pending")
        self.assertFalse(any(x["kind"] == "learned" for x in
                             related_context(self.store, "블로그 글 근거 검증")))
        learning.review(self.store, first["id"], "approve")
        self.assertTrue(any(x["kind"] == "learned" and
                            x["source_status"] == "user_approved" for x in
                            related_context(self.store, "블로그 글 근거 검증")))
        self.store.close()
        self.store = MemoryStore(self.path)
        self.assertTrue(learning.enabled(self.store))
        self.assertEqual(learning.summary(self.store)["approved_count"], 1)
        self.assertEqual(self.store.recent_memories(1)[0]["id"], old["id"])
        self.assertEqual(self.store.list_profile()[0]["value"], "검증부터 시작한다")

    def test_reject_correction_erasures_and_revisions(self):
        learning.set_enabled(self.store, True)
        first = learning.propose(self.store, "communication",
            "대답은 무조건 간결하게 한다", "나는 대답을 좀 더 간결하게 듣고 싶어")
        second = learning.propose(self.store, "goals",
            "이번 달은 영상에 집중한다", "나는 이번 달 영상 작업에 집중할게")
        learning.review(self.store, second["id"], "reject")
        self.assertFalse(any(x["kind"] == "learned" and x["source_id"] == second["id"]
                             for x in related_context(self.store, "이번 달 영상")))
        with self.assertRaises(ValueError):
            learning.correct(self.store, first["id"], "아직 승인 전")
        learning.review(self.store, first["id"], "approve")
        learning.correct(self.store, first["id"], "결론을 먼저 말하고 필요할 때 자세히 설명한다")
        self.assertEqual(self.store.db.execute(
            "SELECT count(*) FROM learned_memory_revisions").fetchone()[0], 1)
        learning.forget(self.store, first["id"])
        self.assertFalse(any(x["kind"] == "learned" for x in
                             related_context(self.store, "결론을 먼저 말하고")))
        self.assertEqual(self.store.db.execute(
            "SELECT count(*) FROM learned_memory_revisions").fetchone()[0], 0)
        self.assertEqual(learning.summary(self.store)["approved_count"], 0)

    def test_approved_tone_is_available_across_unrelated_topics(self):
        learning.set_enabled(self.store, True)
        candidate = learning.propose(self.store, "communication",
            "답변을 할 때 결론부터 간결하게 설명한다",
            "나는 긴 설명보다는 답변을 할 때 결론부터 듣고 싶어")
        self.assertEqual(related_context(self.store, "주말 날씨 알려줘"), [])
        learning.review(self.store, candidate["id"], "approve")
        matched = related_context(self.store, "주말 날씨 알려줘")
        self.assertTrue(any(item["kind"] == "learned" and
                            item["source_id"] == candidate["id"] for item in matched))
        learning.set_enabled(self.store, False)
        self.assertTrue(any(item["kind"] == "learned" for item in
                            related_context(self.store, "주말 날씨 알려줘")))
        self.assertEqual(self.store.db.execute(
            "SELECT count(*) FROM learned_memories WHERE status='approved'").fetchone()[0], 1)

    def test_reject_sensitive_data_and_invalid_status(self):
        learning.set_enabled(self.store, True)
        for raw in ("내 api key: 1234567asdf", "이메일은 test@example.com",
                    "010-1234-5678", "password: abc123", "토큰 sk-abcde1234567890123456789"):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                learning.propose(self.store, "identity", "내 연락처와 계정 설정을 기억한다", raw)
        with self.assertRaises(ValueError):
            learning.propose(self.store, "unknown", "나의 단단한 목표가 있다", "나는 목표가 있다")
        with self.assertRaises(ValueError):
            learning.review(self.store, True, "approve")
        self.assertEqual(learning.summary(self.store)["pending_count"], 0)


class LearningHTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.server = make_server(port=0, db_path=Path(self.temp.name) / "remote.sqlite3")
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.server.RequestHandlerClass.store.close()
        self.temp.cleanup()

    def call(self, path, payload=None, origin=None):
        headers = {"Accept": "application/json"}
        if payload is not None:
            headers["Content-Type"] = "application/json"
        if origin is not None:
            headers["Origin"] = origin
        body = None if payload is None else json.dumps(payload, ensure_ascii=False).encode()
        with urlopen(Request(self.base+path, data=body, headers=headers), timeout=5) as reply:
            return json.load(reply)

    def test_explicit_settings_candidate_review_and_query(self):
        self.assertFalse(self.call("/api/learning")["enabled"])
        with self.assertRaises(HTTPError) as refused:
            self.call("/api/learning/candidate", {"category":"working_style",
                 "content":"블로그 글은 근거를 검증한다",
                 "source_excerpt":"나는 블로그 글의 근거부터 검증한다"})
        self.assertEqual(refused.exception.code, 400)
        self.assertTrue(self.call("/api/learning/enable", {"enabled": True})["enabled"])
        candidate = self.call("/api/learning/candidate", {"category":"working_style",
                 "content":"블로그 글은 근거를 먼저 검증한다",
                 "source_excerpt":"나는 블로그 글은 근거를 먼저 검증하려고 해"})["item"]
        self.assertEqual(candidate["status"], "pending")
        with self.assertRaises(HTTPError) as invalid:
            self.call("/api/learning/review", {"id":candidate["id"], "action":"approve"},
                      origin="https://attacker.example")
        self.assertEqual(invalid.exception.code, 403)
        self.assertEqual(self.call("/api/learning")["pending_count"], 1)
        self.call("/api/learning/review", {"id":candidate["id"],"action":"approve"})
        results = self.call("/api/thinking/context", {"query":"블로그 근거 검증"})
        self.assertTrue(any(item["kind"] == "learned" for item in results["items"]))
        self.call("/api/learning/correct", {"id":candidate["id"],
                                           "content":"블로그 원문 출처를 먼저 검증하고 작성한다"})
        self.call("/api/learning/forget", {"id":candidate["id"]})
        self.assertEqual(self.call("/api/learning")["approved_count"], 0)


if __name__ == "__main__":
    unittest.main()
