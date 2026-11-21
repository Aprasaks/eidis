from pathlib import Path
import tempfile
import threading
import time
import unittest
from jarvis.storage import MemoryStore
from jarvis import action

class Youtube:
    def __init__(self, analytics=None, fail=False, gate=None):
        self.analytics=analytics
        self.fail=fail
        self.gate=gate
        self.called=0
    def summary(self):
        self.called+=1
        if self.gate is not None: self.gate.wait(3)
        if self.fail: raise RuntimeError("private-token-must-not-leak")
        return {"channel_id":"synthetic","channel_title":"테스트 채널","subscriber_count":"12",
                "video_count":"7","channel_views":"100","period_start":"2026-10-01",
                "period_end":"2026-10-28","checked_at":"2026-11-21T01:00:00+00:00",
                "analytics":self.analytics,"oauth_token":"never-store"}

class ActionTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.store=MemoryStore(Path(self.tmp.name)/"data.sqlite")
        self.project=self.store.create_project("테스트 프로젝트")
        self.task=self.store.add_project_task(self.project["id"],"테스트 업무")
        self.store.update_project_task(self.project["id"],self.task["id"],"done")
    def tearDown(self):
        self.store.db.close()
        self.tmp.cleanup()
    def drain(self,runner,job):
        limit=time.monotonic()+4
        while time.monotonic()<limit:
            runner.tick()
            r=action.get_job(self.store,job["id"])
            if r["state"] not in ("queued","running") and runner.active is None: return r
            time.sleep(.01)
        self.fail("job did not settle")
    def test_local_report_real_counts_no_external_read(self):
        provider=Youtube(fail=True)
        runner=action.ActionRunner(self.store,provider)
        job=action.submit(self.store,"project_report")
        result=self.drain(runner,job)
        self.assertEqual(result["state"],"completed")
        self.assertIn("완료 기록 1건",result["summary"])
        self.assertEqual(result["evidence"][0]["data"]["task_count"],1)
        self.assertEqual(provider.called,0)
        self.assertEqual(self.store.get_project(self.project["id"])["tasks"][0]["status"],"done")
        self.assertEqual(len(self.store.list_thoughts()),0)
    def test_overview_partial_and_private_error_not_saved(self):
        runner=action.ActionRunner(self.store,Youtube(fail=True))
        result=self.drain(runner,action.submit(self.store,"overview_report"))
        self.assertEqual(result["state"],"partial")
        self.assertEqual(len(result["evidence"]),2)
        self.assertNotIn("private-token",str(result))
    def test_youtube_nullable_analytics_not_zero(self):
        runner=action.ActionRunner(self.store,Youtube())
        result=self.drain(runner,action.submit(self.store,"youtube_report"))
        self.assertEqual(result["state"],"partial")
        self.assertIn("기간 분석 데이터 미확인",result["report"])
        self.assertNotIn("oauth_token",str(result))
    def test_youtube_success(self):
        runner=action.ActionRunner(self.store,Youtube({"views":42,"estimated_minutes_watched":10.2,"subscribers_gained":2}))
        result=self.drain(runner,action.submit(self.store,"youtube_report"))
        self.assertEqual(result["state"],"completed")
        self.assertIn("기간 조회수 42",result["report"])
    def test_cancel_late_result(self):
        gate=threading.Event()
        runner=action.ActionRunner(self.store,Youtube(gate=gate))
        job=action.submit(self.store,"youtube_report")
        runner.tick()
        self.assertTrue(action.cancel(self.store,job["id"]))
        gate.set()
        result=self.drain(runner,job)
        self.assertEqual(result["state"],"cancelled")
        self.assertEqual(result["report"],"")
        self.assertEqual(result["evidence"],[])
    def test_recover_and_queue_limit(self):
        runner=action.ActionRunner(self.store,Youtube())
        job=action.submit(self.store,"project_report")
        with self.store.db:
            self.store.db.execute("UPDATE action_jobs SET state='running' WHERE id=?",(job["id"],))
        action.recover(self.store)
        self.assertEqual(action.get_job(self.store,job["id"])["state"],"failed")
        for _ in range(action.MAX_PENDING): action.submit(self.store,"project_report")
        with self.assertRaises(ValueError): action.submit(self.store,"project_report")
        with self.assertRaises(ValueError): action.submit(self.store,"delete_files")
        with self.assertRaises(ValueError): action.cancel(self.store,True)
    def test_report_reopen(self):
        runner=action.ActionRunner(self.store,Youtube())
        done=self.drain(runner,action.submit(self.store,"project_report"))
        path=self.store.path
        self.store.db.close()
        self.store=MemoryStore(path)
        self.assertEqual(action.get_job(self.store,done["id"])["report"],done["report"])

if __name__=="__main__": unittest.main()
