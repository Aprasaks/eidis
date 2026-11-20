"""Thinking Core v1.0: local data, bounded context and explicit hypotheses."""
from __future__ import annotations

import json
import sqlite3
import tempfile
import threading
import time
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from jarvis.storage import MemoryStore
from jarvis.thinking import related_context
from jarvis.server import make_server


class ThoughtStoreTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / "thoughts.sqlite3"
        self.db = MemoryStore(self.path)

    def tearDown(self):
        self.db.db.close()
        self.directory.cleanup()

    def test_relevant_sources_are_labeled_and_unrelated_excluded(self):
        project = self.db.create_project("취업 준비", "교육 분야와 개발 분야를 비교한다.")
        self.db.add_project_task(project["id"], "채용요건 검증")
        self.db.add_memory("취업 지원서를 12월에 정리하자", "진로")
        self.db.save_vault(title="취업 자료", content="교육 직무 자격 요건을 검증하기 전이다",
                           category="research", source_type="user_text")
        self.db.save_vault(title="날씨", content="오늘 기온", category="notes",
                           source_type="assistant_response")
        records = related_context(self.db, "자비스, 우리 취업은 어떻게 준비하기로 했지?")
        self.assertTrue(records)
        self.assertTrue(any(x["kind"] == "project" for x in records))
        self.assertTrue(any(x["kind"] == "vault" and x["source_status"] == "user_supplied"
                            for x in records))
        self.assertFalse(any(x["title"] == "날씨" for x in records))
        for item in records:
            self.assertIn("source_id", item)
            self.assertIn("recorded_at", item)
            self.assertLessEqual(len(item["excerpt"]), 260)

    def test_saved_thought_is_hypothesis_and_survives_reopen(self):
        prior = self.db.db.execute("SELECT count(*) FROM thought_records").fetchone()[0]
        self.assertEqual(prior, 0)
        thought = self.db.create_thought("취업과 교육의 우선순위", "교육 분야를 먼저 조사할 가능성이 있다")
        self.assertEqual(thought["status"], "hypothesis")
        self.assertEqual(thought["source"], "assistant_response")
        self.assertEqual(self.db.list_thoughts()[0]["id"], thought["id"])
        self.db.db.close()
        self.db = MemoryStore(self.path)
        self.assertEqual(self.db.get_thought(thought["id"])["status"], "hypothesis")
        result = self.db.review_thought(thought["id"], "rejected", "채용 요건을 충족하지 못함")
        self.assertEqual(result["status"], "rejected")
        self.assertIn("채용 요건", result["review_note"])
        results = related_context(self.db, "취업과 교육 우선순위는?")
        self.assertTrue(any("assistant_thought_rejected" == x["source_status"] for x in results))

    def test_secret_guard_no_unintended_writes(self):
        with self.assertRaises(ValueError):
            self.db.create_thought("키", "password: try this")
        with self.assertRaises(ValueError):
            self.db.create_thought("x", "a" * 1501)
        with self.assertRaises(ValueError):
            self.db.review_thought(1, "verified", "모델 혼자 확정")
        self.assertEqual(self.db.list_thoughts(), [])
        self.assertEqual(related_context(self.db, "자비스"), [])
        self.assertEqual(related_context(self.db, "오늘 뭐해?"), [])

    def test_multiple_existing_records_not_changed(self):
        self.db.add_memory("기존 메모 보존")
        saved = self.db.save_vault(title="원문", content="기존자료의 원문",
                                   source_type="user_text")
        before = self.db.db.execute("SELECT content FROM memories").fetchone()[0]
        _ = related_context(self.db, "기존 원문 다시 보자")
        self.assertEqual(self.db.db.execute("SELECT content FROM memories").fetchone()[0], before)
        self.assertEqual(self.db.get_vault(saved["id"])["content"], "기존자료의 원문")


class ThinkingHttpTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.server = make_server(port=0, db_path=Path(self.directory.name)/"api.sqlite3")
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.worker.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.worker.join(timeout=2)
        self.server.RequestHandlerClass.store.db.close()
        self.directory.cleanup()

    def request(self, path, payload=None, origin=None):
        headers = {"Accept": "application/json"}
        if payload is not None:
            headers["Content-Type"] = "application/json"
        if origin is not None:
            headers["Origin"] = origin
        data = None if payload is None else json.dumps(payload,ensure_ascii=False).encode()
        with urlopen(Request(self.base + path, data=data, headers=headers), timeout=5) as r:
            return json.load(r)

    def test_query_does_not_autosave_thoughts_and_explicit_save_does(self):
        self.server.RequestHandlerClass.store.create_project("DECHIVE", "블로그 검색 유입 검증")
        answer = self.request("/api/thinking/context", {"query":"우리 DECHIVE 블로그 문제는?"})
        self.assertTrue(any(i["kind"] == "project" for i in answer["items"]))
        self.assertEqual(self.request("/api/thoughts")["items"], [])
        response = self.request("/api/thoughts", {
            "topic":"블로그 검색 유입", "hypothesis":"검색 노출이 문제인지부터 확인할 필요가 있다"})
        self.assertEqual(response["thought"]["status"], "hypothesis")
        thought_id = response["thought"]["id"]
        reviewed = self.request("/api/thoughts/review", {
            "id": thought_id, "status":"user_reviewed", "note":"사용자가 검토했으나 실제 결과는 미확인"})
        self.assertEqual(reviewed["thought"]["status"], "user_reviewed")
        self.assertEqual(len(self.request("/api/thoughts")["items"]), 1)

    def test_reject_cross_origin_and_unsafe_status(self):
        with self.assertRaises(HTTPError) as ctx:
            self.request("/api/thoughts", {"topic":"x","hypothesis":"y"},
                         origin="https://bad.example")
        self.assertEqual(ctx.exception.code, 403)
        with self.assertRaises(HTTPError) as ctx:
            self.request("/api/thoughts/review", {"id":1,"status":"verified","note":"설명"})
        self.assertEqual(ctx.exception.code, 400)
        self.assertEqual(self.request("/api/thoughts")["items"], [])


if __name__ == "__main__":
    unittest.main()
