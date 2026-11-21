"""RESEARCH 1.1: literal quote binding, comparison uncertainty and leases."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import json
import tempfile
import unittest
import threading
from urllib.request import Request,urlopen
from urllib.error import HTTPError

from jarvis import verification, research
from jarvis.storage import MemoryStore
from jarvis.server import make_server

SOURCE1="Python is a programming language that lets you work quickly and integrate systems more effectively."
SOURCE2="Python is an interpreted, object-oriented, high-level programming language with dynamic semantics."
SOURCE3="Python is sometimes described as only a compiled language without interpreter support."


def seeded(store, sources=2):
    with store.db:
        job=store.db.execute(
            "INSERT INTO research_jobs(query,state,summary,report,requested_at,updated_at) "
            "VALUES(?,'completed','dummy','old report',?,?)",
            ("What is Python?","2026-11-20T06:00:00+00:00","2026-11-20T06:00:00+00:00")
        ).lastrowid
        for rank,txt,domain in (
            (1,SOURCE1,"python.org"),
            (2,SOURCE2,"docs.python.org"),
            (3,SOURCE3,"thirdparty.example")
        )[:sources]:
            store.db.execute(
                "INSERT INTO research_sources(job_id,rank,title,url,domain,state,checked_at,content_excerpt) "
                "VALUES(?,?,?,?,?,'retrieved',?,?)",
                (job,rank,f"Source {rank}",f"https://{domain}/documentation",
                 domain,"2026-11-20T06:00:00+00:00",txt)
            )
    return job


class VerificationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.path=Path(self.tmp.name)/"verify.sqlite3"
        self.store=MemoryStore(self.path)
        self.job=seeded(self.store,3)
        self.now=datetime.now(timezone.utc).replace(microsecond=0)

    def tearDown(self):
        self.store.db.close()
        self.tmp.cleanup()

    def _claim(self):
        r=verification.enqueue(self.store,self.job)
        result=verification.claim(self.store,self.now)
        self.assertEqual(result["id"],r["id"])
        return result

    def test_model_wrong_source_number_is_rejected(self):
        work=self._claim()
        output=json.dumps({"claims":[
            {"statement":"Python uses dynamic semantics",
             "evidence":[{"rank":1,"quote":SOURCE2,"stance":"supports"}]},
            {"statement":"Python allows rapid work",
             "evidence":[{"rank":1,"quote":SOURCE1,"stance":"supports"}]}
        ],"interpretation":"A proposal, not a certified fact.",
        "next_checks":["Check an independent official spec"]})
        self.assertTrue(verification.finish(self.store,work["id"],work["lease"],"result",output,self.now))
        saved=verification.get_job(self.store,work["id"])
        self.assertEqual(saved["state"],"draft")
        self.assertEqual(len(saved["result"]["claims"]),1)
        self.assertEqual(saved["result"]["claims"][0]["evidence"][0]["rank"],1)
        self.assertEqual(saved["result"]["rejected_citations"],1)
        self.assertIn("인용 연결 거부: 1건",saved["report"])
        self.assertIn("독립 확인 안 됨",saved["report"])
        self.assertEqual(self.store.list_thoughts(),[])
        self.assertEqual(research.get_job(self.store,self.job)["report"],"old report")

    def test_conflict_is_potential_not_verified(self):
        work=self._claim()
        raw=json.dumps({"claims":[{"statement":"Python compilation status",
            "evidence":[{"rank":2,"quote":SOURCE2,"stance":"supports"},
                        {"rank":3,"quote":SOURCE3,"stance":"opposes"}]}],
            "interpretation":"A potential disagreement.","next_checks":["Verify original manuals."]})
        self.assertTrue(verification.finish(self.store,work["id"],work["lease"],"result",raw,self.now))
        saved=verification.get_job(self.store,work["id"])
        claim=saved["result"]["claims"][0]
        self.assertEqual(claim["comparison"],"possible_conflict_requires_review")
        self.assertEqual(claim["claim_status"],"ai_proposed_quote_anchored_unverified")
        self.assertNotIn("사실로 검증 완료",saved["report"])

    def test_same_domain_is_not_cross_source_corrob(self):
        job=verification._validated_model_output(json.dumps({"claims":[{"statement":"Python is useful",
            "evidence":[{"rank":1,"quote":SOURCE1,"stance":"supports"},
                        {"rank":2,"quote":SOURCE2,"stance":"supports"}]}],"interpretation":"","next_checks":[]}),
            [{"rank":1,"url":"https://example.org/a","domain":"example.org","content_excerpt":SOURCE1,
              "claimed_published_at":"","checked_at":"now","source_status":"retrieved"},
             {"rank":2,"url":"https://example.org/b","domain":"example.org","content_excerpt":SOURCE2,
              "claimed_published_at":"","checked_at":"now","source_status":"retrieved"}])
        self.assertEqual(job["claims"][0]["comparison"],"single_domain_or_context_only")
        self.assertEqual(job["rejected_citations"],0)

    def test_all_fake_quotes_means_insufficient_no_hypothesis(self):
        work=self._claim()
        raw=json.dumps({"claims":[{"statement":"This is factual","evidence":[
            {"rank":1,"quote":"This quote does not exist in the source.","stance":"supports"}]}],
            "interpretation":"This should never be stored.","next_checks":["Check." ]})
        verification.finish(self.store,work["id"],work["lease"],"result",raw,self.now)
        saved=verification.get_job(self.store,work["id"])
        self.assertEqual(saved["state"],"insufficient")
        self.assertEqual(saved["result"]["claims"],[])
        self.assertEqual(saved["result"]["interpretation"],"")
        self.assertNotIn("This should never",saved["report"])

    def test_cannot_claim_without_retrieved_sources(self):
        self.store.db.execute("UPDATE research_sources SET state='indexed_only' WHERE job_id=?",(self.job,))
        self.store.db.commit()
        with self.assertRaises(ValueError):
            verification.enqueue(self.store,self.job)

    def test_duplicate_restart_queue_lease_and_cancel(self):
        first=verification.enqueue(self.store,self.job)
        self.assertEqual(first["id"],verification.enqueue(self.store,self.job)["id"])
        run=verification.claim(self.store,self.now)
        self.assertEqual(run["id"],first["id"])
        self.assertIsNone(verification.claim(self.store,self.now))
        self.assertFalse(verification.finish(self.store,run["id"],"0"*32,"result","{}",self.now))
        self.assertTrue(verification.cancel(self.store,run["id"]))
        self.assertFalse(verification.finish(self.store,run["id"],run["lease"],"result","{}",self.now))
        self.store.db.close()
        self.store=MemoryStore(self.path)
        self.assertEqual(verification.get_job(self.store,first["id"])["state"],"cancelled")
        self.assertEqual(len(self.store.list_projects()),0)

    def test_expired_lease_recovers_and_budget_throttles(self):
        work=self._claim()
        again=verification.claim(self.store,self.now+timedelta(seconds=verification.LEASE_SECONDS+1))
        self.assertEqual(again["id"],work["id"])
        self.assertNotEqual(again["lease"],work["lease"])
        self.assertFalse(verification.finish(self.store,work["id"],work["lease"],"result","{}",self.now))
        self.assertTrue(verification.finish(self.store,again["id"],again["lease"],"failed","",
                                            self.now+timedelta(seconds=verification.LEASE_SECONDS+2)))
        self.assertEqual(verification.get_job(self.store,work["id"])["state"],"failed")
        self.assertIsNone(verification.claim(self.store,self.now+timedelta(minutes=5)))

    def test_claim_date_metadata_not_certified(self):
        src={"rank":1,"url":"https://docs.example.org","domain":"docs.example.org",
             "source_status":"retrieved","checked_at":"2026-11-20",
             "claimed_published_at":"2035-01-01T01:00:00Z"}
        assessment=verification.assess(src)
        self.assertIn("미래 날짜",assessment["date_assessment"])
        self.assertEqual(assessment["publisher_identity"],"독립 확인 안 됨")

    def test_loopback_http_contract_and_origin_guard(self):
        self.store.db.close()
        srv=make_server(port=0,db_path=self.path)
        th=threading.Thread(target=srv.serve_forever,daemon=True)
        th.start()
        base=f"http://127.0.0.1:{srv.server_port}"
        def post(path,data,origin=None):
            headers={"Content-Type":"application/json"}
            if origin:headers["Origin"]=origin
            req=Request(base+path,data=json.dumps(data).encode(),headers=headers)
            with urlopen(req,timeout=4) as f:return json.load(f)
        try:
            with self.assertRaises(HTTPError) as ctx:
                post("/api/research/verification/submit",
                     {"research_id":self.job},"https://evil.example")
            ctx.exception.close()
            self.assertEqual(ctx.exception.code,403)
            result=post("/api/research/verification/submit",{"research_id":self.job})
            vid=result["verification"]["id"]
            self.assertEqual(result["verification"]["state"],"queued")
            with urlopen(base+"/api/research/verification?id="+str(vid),timeout=4) as f:
                self.assertEqual(json.load(f)["id"],vid)
            with urlopen(base+"/api/research/verification/status",timeout=4) as f:
                self.assertEqual(json.load(f)["latest_result"]["state"],"queued")
            run=post("/api/research/verification/claim",{})["job"]
            self.assertEqual(run["id"],vid)
            raw=json.dumps({"claims":[{"statement":"Python language","evidence":[
                {"rank":1,"quote":SOURCE1,"stance":"supports"}]}],"interpretation":"Needs checking.",
                "next_checks":["Crosscheck the official manual."]})
            self.assertTrue(post("/api/research/verification/finish",{
                "id":vid,"lease":run["lease"],"outcome":"result","output":raw
            })["accepted"])
            with urlopen(base+"/api/research/verification?id="+str(vid),timeout=4) as f:
                saved=json.load(f)
            self.assertEqual(saved["state"],"draft")
            self.assertIn(SOURCE1,saved["report"])
        finally:
            srv.shutdown();srv.server_close();th.join(timeout=2)
            srv.RequestHandlerClass.store.db.close()
            self.store=MemoryStore(self.path)


if __name__=="__main__":
    unittest.main()
