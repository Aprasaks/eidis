"""Continuity core: real periodic local checks, stable alerts and source status."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import json
import tempfile
import threading
import time
import unittest
from urllib.request import Request, urlopen
from urllib.error import HTTPError

from jarvis.storage import MemoryStore
from jarvis.continuity import scan, snapshot, acknowledge
from jarvis.server import make_server


def at(days=0):
    return datetime(2026, 11, 21, 12, tzinfo=timezone.utc) + timedelta(days=days)


class ContinuityStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "test.sqlite3"
        self.store = MemoryStore(self.path)

    def tearDown(self):
        self.store.db.close()
        self.tmp.cleanup()

    def task(self, name, status="todo", age=0):
        p = self.store.create_project(name+" 프로젝트", "테스트용 목표")
        t = self.store.add_project_task(p["id"], name)
        with self.store.db:
            self.store.db.execute("UPDATE project_tasks SET status=?, updated_at=? WHERE id=?",
                                  (status, at(-age).isoformat(), t["id"]))
        return p["id"], t["id"]

    def test_open_task_reminders_use_record_not_claims_of_missed_deadlines(self):
        _, blocked = self.task("막힌 작업", "blocked")
        _, stale = self.task("갱신되지 않은 작업", age=4)
        self.task("최근 작업", age=1)
        self.task("완료 작업", "done", 10)
        scan(self.store, at())
        result = snapshot(self.store)
        self.assertEqual(result["open_count"], 2)
        self.assertEqual({i["source_id"] for i in result["items"]}, {blocked, stale})
        self.assertEqual(result["last_scan"], at().isoformat(timespec="seconds"))
        self.assertTrue(all(i["evidence"] and "작업 기록" in i["reason"]
                            for i in result["items"]))

    def test_acknowledgement_survives_restart_and_new_evidence_reopens(self):
        pid, tid = self.task("막힌 작업", "blocked", 5)
        scan(self.store, at())
        alert = snapshot(self.store)["items"][0]
        self.assertTrue(acknowledge(self.store, alert["id"]))
        self.assertFalse(acknowledge(self.store, alert["id"]))
        self.store.db.close()
        self.store = MemoryStore(self.path)
        scan(self.store, at(1))
        self.assertEqual(snapshot(self.store)["open_count"], 0)
        with self.store.db:
            self.store.db.execute("UPDATE project_tasks SET updated_at=? WHERE id=?",
                                  (at(1).isoformat(), tid))
        scan(self.store, at(1))
        self.assertEqual(snapshot(self.store)["open_count"], 1)
        self.assertEqual(snapshot(self.store)["items"][0]["id"], alert["id"])
        self.store.update_project_task(pid, tid, "done")
        scan(self.store, at(1))
        self.assertEqual(snapshot(self.store)["open_count"], 0)
        self.assertEqual(self.store.db.execute(
            "SELECT state FROM continuity_alerts WHERE id=?", (alert["id"],)).fetchone()[0],
            "resolved")

    def test_related_source_change_flags_hypothesis_but_never_verifies_it(self):
        thought = self.store.create_thought("광고 전환율 검토", "광고 전환율 비교가 필요하다")
        with self.store.db:
            self.store.db.execute("UPDATE thought_records SET updated_at=? WHERE id=?",
                                  (at().isoformat(), thought["id"]))
        scan(self.store, at())
        self.assertEqual(snapshot(self.store)["open_count"], 0)
        # An unrelated stored AI hypothesis is not new independent evidence.
        other = self.store.create_thought("광고 전환율 비교", "가설 추가")
        with self.store.db:
            self.store.db.execute("UPDATE thought_records SET updated_at=? WHERE id=?",
                                  (at().isoformat(), other["id"]))
        scan(self.store, at())
        self.assertEqual(snapshot(self.store)["open_count"], 0)
        saved = self.store.save_vault(title="광고 전환율 자료", content="광고 전환율 실제 측정 필요",
                                      source_type="user_text")
        scan(self.store, at())
        items = snapshot(self.store)["items"]
        target = next(i for i in items if i["source_id"] == thought["id"])
        self.assertIn("검색 결과가 바뀌었습니다", target["reason"])
        self.assertIn(saved["id"], [e["source_id"] for e in target["evidence"]
                                    if e["kind"] == "vault"])
        self.assertEqual(self.store.get_thought(thought["id"])["status"], "hypothesis")
        self.store.review_thought(thought["id"], "rejected", "근거가 부족했다")
        scan(self.store, at())
        self.assertFalse(any(i["source_id"] == thought["id"]
                             for i in snapshot(self.store)["items"]))

    def test_age_threshold_once_no_automatic_fact_promotion(self):
        t = self.store.create_thought("취업 준비", "지원 방향을 더 검토한다")
        with self.store.db:
            self.store.db.execute("UPDATE thought_records SET updated_at=? WHERE id=?",
                                  (at(-1).isoformat(), t["id"]))
        scan(self.store, at())
        item = snapshot(self.store)["items"][0]
        self.assertIn("24시간", item["reason"])
        acknowledge(self.store, item["id"])
        scan(self.store, at(3))
        self.assertEqual(snapshot(self.store)["open_count"], 0)
        self.assertEqual(self.store.get_thought(t["id"])["status"], "hypothesis")

    def test_invalid_ack_and_no_transcript_or_fact_writes(self):
        with self.assertRaises(ValueError):
            acknowledge(self.store, True)
        scan(self.store, at())
        self.assertEqual(snapshot(self.store)["open_count"], 0)
        for table in ("memories", "personal_profile", "vault_items", "thought_records"):
            self.assertEqual(self.store.db.execute("SELECT count(*) FROM "+table).fetchone()[0], 0)


class ContinuityHTTPTests(unittest.TestCase):
    def test_actual_timer_and_same_origin(self):
        with tempfile.TemporaryDirectory() as folder:
            server = make_server(port=0, db_path=Path(folder)/"test.sqlite3")
            server.continuity_interval = .05
            store = server.RequestHandlerClass.store
            p = store.create_project("검증 프로젝트", "목표")
            t = store.add_project_task(p["id"], "막힌 작업")
            store.update_project_task(p["id"], t["id"], "blocked")
            worker = threading.Thread(target=lambda: server.serve_forever(poll_interval=.02), daemon=True)
            worker.start()
            base = f"http://127.0.0.1:{server.server_port}"
            try:
                until = time.monotonic() + 3
                while True:
                    with urlopen(base+"/api/continuity", timeout=2) as r:
                        payload = json.load(r)
                    if payload["open_count"] > 0 or time.monotonic() > until:
                        break
                    time.sleep(.03)
                self.assertEqual(payload["open_count"], 1)
                self.assertIsNotNone(payload["last_scan"])
                req = Request(base+"/api/continuity/acknowledge",
                    data=json.dumps({"id": payload["items"][0]["id"]}).encode(),
                    headers={"Content-Type":"application/json","Origin":"https://evil.example"})
                with self.assertRaises(HTTPError) as ctx:
                    urlopen(req, timeout=2)
                self.assertEqual(ctx.exception.code, 403)
                req = Request(base+"/api/continuity/acknowledge",
                    data=json.dumps({"id": payload["items"][0]["id"]}).encode(),
                    headers={"Content-Type":"application/json"})
                with urlopen(req, timeout=2) as r:
                    self.assertTrue(json.load(r)["acknowledged"])
                time.sleep(.10)
                with urlopen(base+"/api/continuity", timeout=2) as r:
                    self.assertEqual(json.load(r)["open_count"], 0)
            finally:
                server.shutdown()
                server.server_close()
                worker.join(timeout=2)
                store.db.close()
