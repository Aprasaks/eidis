"""Explicit, bounded RSS morning briefing. No model, paid API or background polling."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from queue import Queue, Empty
from xml.etree import ElementTree as ET
from urllib.parse import urlsplit, urlunsplit
import json
import threading

from .research import read_url, safe_url, clean
from .storage import iso_now

FEEDS = (
    ("국내·종합", "연합뉴스", "https://www.yna.co.kr/rss/news.xml", ("yna.co.kr",)),
    ("국제", "연합뉴스", "https://www.yna.co.kr/rss/international.xml", ("yna.co.kr",)),
    ("국제", "BBC", "https://feeds.bbci.co.uk/news/world/rss.xml", ("bbc.com","bbc.co.uk")),
    ("경제", "연합뉴스", "https://www.yna.co.kr/rss/economy.xml", ("yna.co.kr",)),
    ("AI·기술", "OpenAI 공식 발표", "https://openai.com/news/rss.xml", ("openai.com",)),
    ("AI·기술", "Google 공식 AI 블로그", "https://blog.google/technology/ai/rss/", ("blog.google",)),
)
CATEGORIES = ("국내·종합", "국제", "경제", "AI·기술")
MAX_DAILY = 8
CACHE_SECONDS = 900
KST = timezone(timedelta(hours=9))
MAX_FEED = 2_200_000

def init_schema(db):
    db.execute("""CREATE TABLE IF NOT EXISTS morning_briefings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        state TEXT NOT NULL,
        requested_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        result TEXT NOT NULL DEFAULT '{}'
    )""")

def _host_allowed(host, domains):
    return any(host == domain or host.endswith("."+domain) for domain in domains)

def _date(raw):
    try:
        dt = parsedate_to_datetime(raw)
        if dt.tzinfo is None: return None
        return dt.astimezone(timezone.utc)
    except (ValueError, TypeError, OverflowError):
        return None

def read_feed(feed, now, reader=read_url):
    category, name, url, domains = feed
    status = {"category":category,"name":name,"url":url,"state":"unavailable",
              "checked_at":iso_now(),"eligible":0}
    try:
        raw, final, _ = reader(url, MAX_FEED, 6)
        # Accept only the fixed publisher domains, never arbitrary search URLs.
        final_host = safe_url(final,lookup=False)
        feed_host = safe_url(url,lookup=False)
        if final_host != feed_host and not _host_allowed(final_host,domains):
            raise ValueError("unexpected_publisher")
        if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
            raise ValueError("unsafe_xml")
        root=ET.fromstring(raw)
        if root.tag != "rss" or root.find("channel") is None:
            raise ValueError("invalid_rss")
        articles=[]
        for node in root.findall("./channel/item")[:1500]:
            published=_date(node.findtext("pubDate",""))
            if published is None or not now-timedelta(hours=24) <= published <= now:
                continue
            link=(node.findtext("link","") or "").strip()
            try: host=safe_url(link,lookup=False)
            except ValueError: continue
            if not _host_allowed(host,domains): continue
            title=clean(node.findtext("title",""),180)
            if not title or title.startswith(('[부고]','[인사]','[게시판]','[동정]')): continue
            p=urlsplit(link)
            canonical=urlunsplit((p.scheme,p.netloc,p.path,"",""))
            articles.append({"category":category,"publisher":name,"title":title,
                "url":link,"canonical":canonical,"published_at":published.isoformat(timespec="seconds"),
                "excerpt":clean(node.findtext("description",""),150),
                "evidence":"publisher_rss_only","feed_url":url})
        status.update(state="read",eligible=len(articles),checked_at=iso_now())
        return status,articles
    except Exception:
        status["checked_at"]=iso_now()
        return status,[]

def collect(now=None,reader=read_url,feeds=FEEDS):
    now=now or datetime.now(timezone.utc)
    with ThreadPoolExecutor(max_workers=4) as pool:
        pairs=list(pool.map(lambda feed:read_feed(feed,now,reader),feeds))
    statuses=[s for s,_ in pairs]
    all_items=[article for _,items in pairs for article in items]
    all_items.sort(key=lambda x:x["published_at"],reverse=True)
    # Specialized categories take precedence over the general feed. Exact
    # URL/title dedup is not independent reporting or event-level dedup.
    seen_urls=set(); seen_titles=set(); groups={c:[] for c in CATEGORIES}
    for cat in ("국제","경제","AI·기술","국내·종합"):
        for item in all_items:
            if item["category"]!=cat or len(groups[cat])>=3: continue
            title_key="".join(c.lower() for c in item["title"] if c.isalnum())
            if item["canonical"] in seen_urls or title_key in seen_titles: continue
            seen_urls.add(item["canonical"]);seen_titles.add(title_key)
            item=dict(item);del item["canonical"]
            groups[cat].append(item)
    articles=[a for cat in CATEGORIES for a in groups[cat]]
    ok=sum(s["state"]=="read" for s in statuses)
    state=("failed" if not ok else "partial" if ok<len(statuses) else
           "completed" if articles else "no_news")
    return state,{"window_start":(now-timedelta(hours=24)).isoformat(timespec="seconds"),
                  "window_end":now.isoformat(timespec="seconds"),
                  "collected_at":iso_now(),"feeds":statuses,"articles":articles,
                  "scope":"최근 24시간·발행처 RSS. 원문 본문 및 사실성은 별도 검증 필요."}

def get_job(store,job_id):
    if type(job_id) is not int or job_id<1: raise ValueError("브리핑 번호 오류")
    row=store.db.execute("SELECT * FROM morning_briefings WHERE id=?",(job_id,)).fetchone()
    if row is None: raise ValueError("브리핑 없음")
    result=dict(row);result["result"]=json.loads(result["result"])
    return result

def submit(store,now=None):
    now=now or datetime.now(timezone.utc)
    latest=store.db.execute("SELECT * FROM morning_briefings ORDER BY id DESC LIMIT 1").fetchone()
    if latest:
        age=(now-datetime.fromisoformat(latest["requested_at"])).total_seconds()
        if latest["state"] in ("queued","running") or (0<=age<CACHE_SECONDS and
                latest["state"] in ("completed","partial","no_news")):
            return get_job(store,latest["id"])
        if latest["state"]=="failed" and 0<=age<60:
            return get_job(store,latest["id"])
    threshold=(now-timedelta(hours=24)).isoformat(timespec="seconds")
    if store.db.execute("SELECT count(*) FROM morning_briefings WHERE requested_at>=?",(threshold,)).fetchone()[0]>=MAX_DAILY:
        raise ValueError("24시간 브리핑 조회 한도에 도달했습니다.")
    ts=now.isoformat(timespec="seconds")
    with store.db:
        cur=store.db.execute("INSERT INTO morning_briefings(state,requested_at,updated_at) VALUES('queued',?,?)",(ts,ts))
    return get_job(store,cur.lastrowid)

class BriefingRunner:
    def __init__(self,store,collector=collect):
        self.store=store
        self.collector=collector
        self.events=Queue()
        self.active=None
        with store.db:
            store.db.execute("UPDATE morning_briefings SET state='failed',updated_at=? WHERE state='running'",(iso_now(),))
    def _work(self,job_id):
        try: state,result=self.collector()
        except Exception: state,result="failed",{}
        self.events.put((job_id,state,result))
    def tick(self):
        try:
            while True:
                job_id,state,result=self.events.get_nowait()
                with self.store.db:
                    self.store.db.execute("UPDATE morning_briefings SET state=?,result=?,updated_at=? WHERE id=? AND state='running'",
                        (state,json.dumps(result,ensure_ascii=False),iso_now(),job_id))
                if self.active==job_id: self.active=None
        except Empty: pass
        if self.active is not None: return
        row=self.store.db.execute("SELECT id FROM morning_briefings WHERE state='queued' ORDER BY id LIMIT 1").fetchone()
        if row:
            job_id=row[0]
            with self.store.db:
                self.store.db.execute("UPDATE morning_briefings SET state='running',updated_at=? WHERE id=?",(iso_now(),job_id))
            self.active=job_id
            threading.Thread(target=self._work,args=(job_id,),daemon=True).start()
