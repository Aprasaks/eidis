"""Explicit, bounded web research with real URLs and source statuses.

No execution from pages, no cookies or browser automation, no unverified
claims presented as independently verified facts.
"""
from __future__ import annotations
from datetime import datetime, timezone, timedelta
from html import unescape
from html.parser import HTMLParser
from ipaddress import ip_address
from queue import Queue, Empty
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler
from xml.etree import ElementTree
import json
import re
import socket
import threading

from .storage import iso_now

MAX_RESULTS = 8
MAX_FETCHES = 4
MAX_DAILY = 12
USER_AGENT = "DECHIVE-JARVIS-Research/1.0 (local personal research)"
BAD_TAGS = {"script","style","svg","noscript","nav","footer","header","form"}


def init_schema(db):
    db.executescript("""
        CREATE TABLE IF NOT EXISTS research_jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            query TEXT NOT NULL, state TEXT NOT NULL,
            progress TEXT NOT NULL DEFAULT '', summary TEXT NOT NULL DEFAULT '',
            report TEXT NOT NULL DEFAULT '', requested_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS research_sources (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job_id INTEGER NOT NULL REFERENCES research_jobs(id),
            rank INTEGER NOT NULL, title TEXT NOT NULL,
            url TEXT NOT NULL, domain TEXT NOT NULL,
            search_excerpt TEXT NOT NULL DEFAULT '',
            state TEXT NOT NULL DEFAULT 'discovered',
            claimed_published_at TEXT NOT NULL DEFAULT '',
            checked_at TEXT NOT NULL DEFAULT '',
            content_excerpt TEXT NOT NULL DEFAULT '',
            reason TEXT NOT NULL DEFAULT '',
            UNIQUE(job_id,rank)
        );
        CREATE INDEX IF NOT EXISTS research_jobs_status_idx ON research_jobs(state,id);
        CREATE INDEX IF NOT EXISTS research_sources_job_idx ON research_sources(job_id,rank);
    """)


def valid_id(value):
    if type(value) is not int or not 1 <= value <= 1000000000:
        raise ValueError("조사 번호가 올바르지 않습니다.")
    return value


def valid_query(value):
    if not isinstance(value,str):
        raise ValueError("조사 질문을 입력해 주세요.")
    s=" ".join(value.strip().split())
    if not 3 <= len(s) <= 160 or any(ord(c)<32 for c in s):
        raise ValueError("조사 질문은 3~160자로 작성해 주세요.")
    if any(t in s.lower() for t in ("password:","api_key=","access_token=","비밀번호:")) or re.search(
        r"(?:sk-[a-zA-Z0-9_-]{20,}|gh[pousr]_[a-zA-Z0-9_]{24,})",s):
        raise ValueError("인증정보를 검색어로 전송하지 않습니다.")
    return s


def submit(store,raw):
    query=valid_query(raw)
    threshold=(datetime.now(timezone.utc)-timedelta(hours=24)).isoformat(timespec="seconds")
    with store.db:
        if store.db.execute("SELECT count(*) FROM research_jobs WHERE state IN ('queued','running')").fetchone()[0]>=6:
            raise ValueError("동시에 접수 가능한 조사 요청은 6건입니다.")
        if store.db.execute("SELECT count(*) FROM research_jobs WHERE requested_at>?",(threshold,)).fetchone()[0]>=MAX_DAILY:
            raise ValueError("24시간 조사는 최대 12건으로 제한됩니다.")
        now=iso_now()
        row=store.db.execute(
            "INSERT INTO research_jobs(query,state,requested_at,updated_at) VALUES(?,'queued',?,?)",
            (query,now,now))
    return get_job(store,row.lastrowid)


def get_job(store,job_id,include_sources=True):
    row=store.db.execute("SELECT * FROM research_jobs WHERE id=?",(valid_id(job_id),)).fetchone()
    if row is None:raise ValueError("조사 기록을 찾을 수 없습니다.")
    out=dict(row)
    if include_sources:
        out["sources"]=[dict(x) for x in store.db.execute(
            "SELECT rank,title,url,domain,search_excerpt,state,claimed_published_at,"
            "checked_at,content_excerpt,reason FROM research_sources WHERE job_id=? ORDER BY rank",
            (job_id,))]
    return out


def status(store):
    counts=dict(store.db.execute("SELECT state,count(*) FROM research_jobs GROUP BY state"))
    items=[dict(x) for x in store.db.execute(
        "SELECT id,query,state,progress,summary,requested_at,updated_at "
        "FROM research_jobs ORDER BY id DESC LIMIT 8")]
    return {"counts":counts,"items":items,
            "latest_sources":get_job(store,items[0]["id"])["sources"] if items else []}


def cancel(store,job_id):
    with store.db:
        return store.db.execute(
            "UPDATE research_jobs SET state='cancelled',progress=?,updated_at=? "
            "WHERE id=? AND state IN ('queued','running')",
            ("사용자가 중단했습니다. 도착하는 조회 결과는 버립니다.",iso_now(),valid_id(job_id))).rowcount==1


def recover(store):
    with store.db:
        store.db.execute("UPDATE research_jobs SET state='failed',progress=?,updated_at=? WHERE state='running'",
                         ("앱이 종료되어 조사가 중단되었습니다. 결과를 완료로 표시하지 않습니다.",iso_now()))


def safe_url(value,lookup=True):
    try:
        p=urlsplit(value)
        host=p.hostname
        port=p.port
    except (ValueError,TypeError):
        raise ValueError("unsafe_url") from None
    if (not isinstance(value,str) or len(value)>2048 or p.scheme!="https"
        or not host or p.username or p.password or port not in (None,443)
        or not re.fullmatch(r"[a-zA-Z0-9.-]{3,253}",host)
        or any(host.endswith(s) for s in (".local",".localhost",".internal",".test",".invalid"))):
        raise ValueError("unsafe_url")
    if lookup:
        try:ips={r[4][0] for r in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)}
        except OSError:raise ValueError("dns_failed") from None
        if not ips or any(not ip_address(ip).is_global for ip in ips):
            raise ValueError("nonpublic_address")
    return host.lower()


class CheckedRedirect(HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        safe_url(newurl)
        return super().redirect_request(req,fp,code,msg,headers,newurl)


def read_url(url,limit,timeout):
    safe_url(url)
    req=Request(url,headers={"User-Agent":USER_AGENT,
                              "Accept":"text/html,text/plain,application/rss+xml,application/xml;q=0.8",
                              "Accept-Encoding":"identity"})
    opener=build_opener(ProxyHandler({}),CheckedRedirect())
    with opener.open(req,timeout=timeout) as response:
        mime=response.headers.get("Content-Type","").split(";")[0].strip().lower()
        if mime not in ("text/html","text/plain","application/rss+xml","application/xml","text/xml","application/xhtml+xml"):
            raise ValueError("unsupported_content")
        raw=response.read(limit+1)
        if len(raw)>limit:raise ValueError("too_large")
        return raw,response.geturl(),mime


def clean(text,limit=300):
    return " ".join(unescape(re.sub(r"<[^>]+>"," ",text or "")).split())[:limit]


def search_rss(query):
    url="https://www.bing.com/search?"+urlencode({"format":"rss","q":query})
    data,_,_=read_url(url,170000,8)
    root=ElementTree.fromstring(data)
    hits=[]; seen=set()
    for node in root.findall(".//item"):
        url=(node.findtext("link") or "").strip()
        try:domain=safe_url(url,lookup=False)
        except ValueError:continue
        title=clean(node.findtext("title") or "",180)
        if not title or url in seen or domain in ("bing.com","www.bing.com"):continue
        seen.add(url)
        hits.append({"title":title,"url":url,"domain":domain,
                     "search_excerpt":clean(node.findtext("description") or "",330),
                     "claimed_published_at":clean(node.findtext("pubDate") or "",80)})
        if len(hits)>=MAX_RESULTS:break
    return hits


class PageText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocked=[]
        self.chunks=[]
        self.date=""
    def handle_starttag(self,tag,attrs):
        if tag in BAD_TAGS:self.blocked.append(tag)
        if tag=="meta":
            a=dict(attrs)
            key=(a.get("property") or a.get("name") or "").lower()
            if key in ("article:published_time","datepublished","pubdate","date"):
                self.date=self.date or clean(a.get("content",""),80)
    def handle_endtag(self,tag):
        if tag in BAD_TAGS and self.blocked and self.blocked[-1]==tag:self.blocked.pop()
    def handle_data(self,text):
        if not self.blocked and len(self.chunks)<350:
            t=" ".join(text.split())
            if len(t)>27:self.chunks.append(t[:500])


def fetch_page(url):
    raw,final,mime=read_url(url,240000,7)
    if mime=="text/plain":
        text=clean(raw.decode("utf-8","replace"),2400)
        if len(text)<50:raise ValueError("not_readable")
        return {"content_excerpt":text,"claimed_published_at":""}
    parser=PageText()
    parser.feed(raw.decode("utf-8","replace"))
    text=clean(" ".join(parser.chunks),2400)
    if len(text)<60:raise ValueError("not_readable")
    return {"content_excerpt":text,"claimed_published_at":parser.date}


def report(job,sources):
    found=sum(s["state"]=="retrieved" for s in sources)
    lines=["# DECHIVE RESEARCH / 실제 수집 근거","",
           "조사: "+job["query"],f"검색 결과 {len(sources)}건 · 원문 수집 {found}건",
           "원문을 열었다는 사실은 내용의 진실성 검증을 뜻하지 않습니다.",
           "발행일은 출처가 표시한 날짜이며 독립 검증되지 않았습니다.",""]
    for s in sources:
        lines.extend([f"## [{s['rank']}] {s['title'][:140]}",
                      "주소: "+s["url"],
                      "상태: "+s["state"]+" / 확인: "+(s["checked_at"] or "원문 미조회")])
        if s["claimed_published_at"]:lines.append("표시 날짜(미검증): "+s["claimed_published_at"])
        if s["content_excerpt"]:lines.append("원문 발췌: "+s["content_excerpt"][:620])
        elif s["search_excerpt"]:lines.append("검색 설명(원문 미확인): "+s["search_excerpt"][:250])
        if s["reason"]:lines.append("이유: "+s["reason"])
        lines.append("")
    lines.extend(["## 추가 검증이 필요한 점",
        f"읽을 수 있었던 출처의 도메인 {len({s['domain'] for s in sources if s['state']=='retrieved'})}개. "
        "각 출처의 공식성·독립성·최신성 및 상충하는 근거는 별도로 검토해야 합니다."])
    return "\n".join(lines)[:16000]


class ResearchRunner:
    """Worker fetches untrusted network data; only main server thread writes DB."""
    def __init__(self,store,searcher=search_rss,fetcher=fetch_page):
        self.store=store
        self.searcher=searcher
        self.fetcher=fetcher
        self.events=Queue()
        self.active=None
        recover(store)

    def _work(self,job_id,query,stop):
        try:
            hits=self.searcher(query)[:MAX_RESULTS]
            self.events.put(("found",job_id,hits))
            for i,hit in enumerate(hits):
                if stop.is_set():break
                if i>=MAX_FETCHES:
                    self.events.put(("page",job_id,i,{"state":"indexed_only",
                                                    "reason":"수집 제한에 따라 색인만 표시"}))
                    continue
                try:
                    page=self.fetcher(hit["url"])
                    self.events.put(("page",job_id,i,{"state":"retrieved",**page}))
                except Exception as exc:
                    label=str(exc)
                    reason=label if label in ("unsafe_url","nonpublic_address","dns_failed",
                        "unsupported_content","too_large","not_readable") else "source_unavailable"
                    self.events.put(("page",job_id,i,{"state":"blocked" if reason in ("unsafe_url","nonpublic_address") else "unavailable",
                                                    "reason":reason}))
        except Exception:self.events.put(("search_error",job_id))
        finally:self.events.put(("end",job_id))

    def tick(self):
        if self.active:
            job_id,stop=self.active
            state=self.store.db.execute("SELECT state FROM research_jobs WHERE id=?",(job_id,)).fetchone()
            if state is None or state[0]!="running":stop.set()
        while True:
            try:kind,job_id,*args=self.events.get_nowait()
            except Empty:break
            row=self.store.db.execute("SELECT state FROM research_jobs WHERE id=?",(job_id,)).fetchone()
            if kind=="end":
                if self.active and self.active[0]==job_id:
                    if row and row[0]=="running":self._finish(job_id)
                    self.active=None
                continue
            if not row or row[0]!="running":continue
            if kind=="found":
                with self.store.db:
                    for i,hit in enumerate(args[0]):
                        self.store.db.execute("INSERT OR IGNORE INTO research_sources "
                            "(job_id,rank,title,url,domain,search_excerpt,claimed_published_at) "
                            "VALUES(?,?,?,?,?,?,?)",
                            (job_id,i+1,hit["title"],hit["url"],hit["domain"],
                             hit.get("search_excerpt",""),hit.get("claimed_published_at","")))
                    self.store.db.execute("UPDATE research_jobs SET progress=?,updated_at=? WHERE id=?",
                                          (f"검색 {len(args[0])}건 · 원문 수집 중",iso_now(),job_id))
            if kind=="page":
                index,detail=args
                with self.store.db:
                    self.store.db.execute(
                        "UPDATE research_sources SET state=?,reason=?,checked_at=?,content_excerpt=?,"
                        "claimed_published_at=CASE WHEN ?<>'' THEN ? ELSE claimed_published_at END "
                        "WHERE job_id=? AND rank=?",
                        (detail["state"],detail.get("reason",""),iso_now(),
                         detail.get("content_excerpt",""),detail.get("claimed_published_at",""),
                         detail.get("claimed_published_at",""),job_id,index+1))
                    n=self.store.db.execute("SELECT count(*) FROM research_sources "
                        "WHERE job_id=? AND state<>'discovered'",(job_id,)).fetchone()[0]
                    self.store.db.execute("UPDATE research_jobs SET progress=?,updated_at=? WHERE id=?",
                                          (f"출처 {n}건 처리",iso_now(),job_id))
        if self.active:return
        row=self.store.db.execute("SELECT id,query FROM research_jobs WHERE state='queued' ORDER BY id LIMIT 1").fetchone()
        if not row:return
        job_id,query=row
        with self.store.db:
            self.store.db.execute("UPDATE research_jobs SET state='running',progress=?,updated_at=? WHERE id=?",
                                  ("웹 검색 요청 중",iso_now(),job_id))
        stop=threading.Event()
        self.active=(job_id,stop)
        threading.Thread(target=self._work,args=(job_id,query,stop),daemon=True,name="dechive-research").start()

    def _finish(self,job_id):
        sources=get_job(self.store,job_id)["sources"]
        found=sum(s["state"]=="retrieved" for s in sources)
        state="completed" if sources and found==min(len(sources),MAX_FETCHES) else (
            "partial" if sources else "failed")
        summary=f"검색 {len(sources)}건 / 원문 {found}건 확인"
        with self.store.db:
            self.store.db.execute("UPDATE research_jobs SET state=?,summary=?,progress=?,updated_at=? WHERE id=? AND state='running'",
                                  (state,summary,"조사 종료",iso_now(),job_id))
            job=get_job(self.store,job_id,include_sources=False)
            self.store.db.execute("UPDATE research_jobs SET report=? WHERE id=? AND state=?",
                                  (report(job,sources),job_id,state))
