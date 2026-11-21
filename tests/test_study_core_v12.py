from datetime import datetime, timedelta, timezone
from pathlib import Path
import tempfile
import unittest
from jarvis.storage import MemoryStore
from jarvis import study

class StudyCoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.path=Path(self.tmp.name)/"test.sqlite3"
        self.store=MemoryStore(self.path)
        self.now=datetime.now(timezone.utc).replace(microsecond=0)
    def tearDown(self):
        self.store.db.close()
        self.tmp.cleanup()
    def register(self, topic="광고 전환율", premise="이전 가설"):
        return study.create_topic(self.store,topic,premise)
    def test_explicit_scope_source_filter_dedup(self):
        self.store.save_vault(title="광고 전환율 자료",content="광고 전환율 실제 비교",source_type="user_text")
        self.store.save_vault(title="광고 전환율 AI",content="광고 전환율 AI 주장",source_type="assistant_response")
        study.schedule(self.store,self.now)
        self.assertIsNone(study.claim(self.store,self.now))
        idx=self.register()
        self.assertEqual(idx,self.register())
        study.schedule(self.store,self.now)
        study.schedule(self.store,self.now)
        job=study.claim(self.store,self.now)
        self.assertIsNotNone(job)
        self.assertEqual(len(job["evidence"]),1)
        self.assertEqual(job["evidence"][0]["source_status"],"user_supplied")
        self.assertIsNone(study.claim(self.store,self.now))
        self.assertTrue(study.finish(self.store,job["id"],job["lease"],"draft","대안: 비교가 필요합니다.",self.now))
        self.assertEqual(study.get_draft(self.store,job["id"])["source_status"],"ai_generated_unverified")
        self.assertEqual(study.status(self.store)["draft_count"],1)
        self.assertEqual(self.store.list_thoughts(),[])
        study.schedule(self.store,self.now)
        self.assertIsNone(study.claim(self.store,self.now))
        self.store.db.close()
        self.store=MemoryStore(self.path)
        self.assertEqual(study.get_draft(self.store,job["id"])["result"],"대안: 비교가 필요합니다.")
    def test_change_creates_fresh_job_and_stale_result_rejected(self):
        self.register()
        study.schedule(self.store,self.now)
        job=study.claim(self.store,self.now)
        self.store.add_memory("광고 전환율 자료 변경")
        study.schedule(self.store,self.now+timedelta(seconds=1))
        self.assertTrue(study.finish(self.store,job["id"],job["lease"],"draft","오래된 결과",self.now+timedelta(seconds=2)))
        self.assertEqual(study.status(self.store)["counts"]["cancelled"],1)
        new=study.claim(self.store,self.now+timedelta(seconds=3))
        self.assertIsNotNone(new)
        self.assertNotEqual(job["id"],new["id"])
        self.assertTrue(new["evidence"])
        self.assertFalse(study.finish(self.store,job["id"],job["lease"],"draft","중복",self.now))
    def test_stop_and_pause_never_promote_or_run(self):
        topic=self.register()
        study.schedule(self.store,self.now)
        job=study.claim(self.store,self.now)
        study.set_enabled(self.store,False)
        self.assertIsNone(study.claim(self.store,self.now))
        self.assertTrue(study.finish(self.store,job["id"],job["lease"],"draft","중단 후 초안",self.now))
        self.assertEqual(study.status(self.store)["draft_count"],0)
        study.set_enabled(self.store,True)
        self.assertTrue(study.stop_topic(self.store,topic))
        self.assertIsNone(study.claim(self.store,self.now+timedelta(minutes=10)))
        self.assertFalse(study.finish(self.store,job["id"],job["lease"],"draft","중단된 결과",self.now))
    def test_lease_crash_recovers_and_attempt_limit(self):
        self.register()
        study.schedule(self.store,self.now)
        job=study.claim(self.store,self.now)
        later=self.now+timedelta(seconds=study.LEASE_SECONDS+1)
        retry=study.claim(self.store,later)
        self.assertEqual(job["id"],retry["id"])
        self.assertNotEqual(job["lease"],retry["lease"])
        self.assertFalse(study.finish(self.store,job["id"],job["lease"],"draft","만료",later))
        self.assertTrue(study.finish(self.store,retry["id"],retry["lease"],"failed",now=later))
        self.assertEqual(study.status(self.store)["counts"]["failed"],1)
        self.assertIsNone(study.claim(self.store,later+timedelta(minutes=10)))
    def test_daily_budget_and_no_external_actions(self):
        for i in range(5): self.register(f"테스트 주제 {i}","")
        study.schedule(self.store,self.now)
        for _ in range(study.DAILY_LIMIT):
            job=study.claim(self.store,self.now)
            self.assertIsNotNone(job)
            self.assertTrue(study.finish(self.store,job["id"],job["lease"],"draft","검증 전 대안",self.now))
        self.assertIsNone(study.claim(self.store,self.now))
        self.assertEqual(study.status(self.store)["remaining"],0)
        self.assertEqual(self.store.list_thoughts(),[])
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM activity").fetchone()[0],0)
    def test_secret_and_bad_lease_rejected(self):
        with self.assertRaises(ValueError): self.register("password: test")
        with self.assertRaises(ValueError): study.set_enabled(self.store,"false")
        with self.assertRaises(ValueError): study.finish(self.store,1,"x","draft","test")
if __name__ == "__main__": unittest.main()
