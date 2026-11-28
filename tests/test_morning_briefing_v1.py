from datetime import datetime,timedelta,timezone
from email.utils import format_datetime
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from xml.sax.saxutils import escape
import json
import threading
import time
import unittest

from jarvis import briefing
from jarvis.storage import MemoryStore
from jarvis.server import make_server

NOW=datetime(2026,11,21,11,0,tzinfo=timezone.utc)

def rss(rows):
    return ('<rss version="2.0"><channel>'+''.join(
        '<item><title>'+escape(title)+'</title><link>'+escape(url)+
        '</link><pubDate>'+escape(date)+'</pubDate><description>Publisher excerpt</description></item>'
        for title,url,date in rows)+'</channel></rss>').encode()

class BriefingTest(unittest.TestCase):
    def setUp(self):
        self.tmp=TemporaryDirectory()
        self.path=Path(self.tmp.name)/"test.sqlite3"
    def tearDown(self):self.tmp.cleanup()
    def test_freshness_scope_dedup_and_wrong_domain(self):
        feeds=briefing.FEEDS[:2]
        date=format_datetime(NOW-timedelta(hours=2))
        recent="https://www.yna.co.kr/view/RECENT"
        rows=[("기사",recent,date),("오래된 기사","https://www.yna.co.kr/view/OLD",format_datetime(NOW-timedelta(hours=25))),
              ("미래 날짜","https://www.yna.co.kr/view/FUTURE",format_datetime(NOW+timedelta(hours=1))),
              ("다른 사이트","https://example.com/news",date),("날짜 없음","https://www.yna.co.kr/view/NODATE",""),
              ("[부고] 제외","https://www.yna.co.kr/view/OBIT",date)]
        def reader(url,*_):
            return rss(rows),url,"application/xml"
        state,result=briefing.collect(NOW,reader,feeds)
        self.assertEqual(state,"completed")
        self.assertEqual(len(result["articles"]),1)
        article=result["articles"][0]
        self.assertEqual(article["category"],"국제")
        self.assertEqual(article["url"],recent)
        self.assertEqual(article["evidence"],"publisher_rss_only")
        self.assertEqual(result["window_end"],NOW.isoformat(timespec="seconds"))
    def test_empty_feed_is_not_failure(self):
        state,r=briefing.collect(NOW,lambda url,*_: (rss([]),url,"application/xml"),briefing.FEEDS[:1])
        self.assertEqual(state,"no_news")
        self.assertEqual(r["articles"],[])
        self.assertEqual(r["feeds"][0]["state"],"read")
    def test_partial_and_failure_xml(self):
        def reader(url,*_):
            if url==briefing.FEEDS[0][2]:return rss([]),url,"application/xml"
            return b'<!DOCTYPE rss [<!ENTITY boom "abc">]><rss/>',url,"text/xml"
        state,r=briefing.collect(NOW,reader,briefing.FEEDS[:2])
        self.assertEqual(state,"partial")
        self.assertEqual([x["state"] for x in r["feeds"]],["read","unavailable"])
        state,_=briefing.collect(NOW,reader,briefing.FEEDS[1:2])
        self.assertEqual(state,"failed")
    def test_cache_and_daily_limit(self):
        store=MemoryStore(self.path)
        try:
            a=briefing.submit(store,NOW)
            self.assertEqual(a["state"],"queued")
            self.assertEqual(briefing.submit(store,NOW)["id"],a["id"])
            with store.db:store.db.execute("UPDATE morning_briefings SET state='completed'")
            self.assertEqual(briefing.submit(store,NOW+timedelta(minutes=5))["id"],a["id"])
            for i in range(1,8):
                b=briefing.submit(store,NOW+timedelta(minutes=16*i))
                with store.db:store.db.execute("UPDATE morning_briefings SET state='completed' WHERE id=?",(b["id"],))
            with self.assertRaises(ValueError):briefing.submit(store,NOW+timedelta(hours=3))
        finally:store.db.close()
    def test_loopback_and_async_persistence(self):
        server=make_server(port=0,db_path=self.path)
        server.briefing_runner.collector=lambda:briefing.collect(
            NOW,lambda url,*_:(rss([]),url,"application/xml"),briefing.FEEDS[:1])
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        base=f"http://127.0.0.1:{server.server_port}"
        def post(data,origin=None):
            headers={"Content-Type":"application/json"}
            if origin: headers["Origin"]=origin
            with urlopen(Request(base+"/api/briefing/submit",data=json.dumps(data).encode(),headers=headers),timeout=3) as res:
                return json.load(res)
        try:
            with self.assertRaises(HTTPError) as err:post({"url":"http://127.0.0.1/"})
            self.assertEqual(err.exception.code,400)
            with self.assertRaises(HTTPError) as err:post({},"https://example.com")
            self.assertEqual(err.exception.code,403)
            job=post({})
            for _ in range(80):
                with urlopen(base+"/api/briefing/job?id="+str(job["id"]),timeout=3) as r:job=json.load(r)
                if job["state"] not in ("queued","running"):break
                time.sleep(.025)
            self.assertEqual(job["state"],"no_news")
            self.assertEqual(post({})["id"],job["id"])
        finally:
            server.shutdown();server.server_close();thread.join(timeout=2)
            server.RequestHandlerClass.store.db.close()
        store=MemoryStore(self.path)
        try:self.assertEqual(briefing.get_job(store,job["id"])["state"],"no_news")
        finally:store.db.close()
    def test_ui_routes_before_model_and_preserves_mini(self):
        root=Path(__file__).resolve().parents[1]/"macos/Sources/EidisMac"
        chat=(root/"JarvisOverlayConversation.swift").read_text()
        ui=(root/"JarvisFullscreenOverlay.swift").read_text()
        # P3 스킬 구조: 브리핑은 스킬 규칙(runSkills)으로 모델보다 먼저 판별되고, 패널은 showOnly로 하나만 연다
        self.assertLess(chat.index("if let routed = await runSkills(prompt, token: token) { return routed }"),
                        chat.index("if let clock = JarvisLocalClock.parse(prompt)"))
        self.assertIn("JarvisBriefingIntent.parse(p).map",chat)
        self.assertIn("if plan.opens { showOnly(rule.panel) }",chat)
        self.assertIn("briefingVisible = true\n        briefingJob = nil",chat)
        self.assertIn("JarvisMorningBriefingView(job:dialogue.briefingJob",ui)

if __name__=="__main__":unittest.main()
