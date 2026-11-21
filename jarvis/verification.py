"""Model-independent quote anchoring and bounded, explicit verification queue.

This is evidence-link checking, NOT truth certification or publisher
authentication. Qwen may propose claims, but only literal quotes from already
retrieved pages are accepted into the report.
"""
from __future__ import annotations

from datetime import datetime, timezone, timedelta
from email.utils import parsedate_to_datetime
from hashlib import sha256
from uuid import uuid4
import json
import re

from .storage import iso_now
from . import research

MAX_DAILY = 3
MAX_ATTEMPTS = 2
LEASE_SECONDS = 180
MAX_CLAIMS = 3
MAX_EVIDENCE = 3
MAX_OUTPUT = 10000


def init_schema(db):
    db.executescript("""
        CREATE TABLE IF NOT EXISTS research_verifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            research_id INTEGER NOT NULL REFERENCES research_jobs(id),
            fingerprint TEXT NOT NULL,
            evidence_json TEXT NOT NULL,
            state TEXT NOT NULL CHECK(state IN
                ('queued','running','draft','insufficient','failed','cancelled')),
            attempt INTEGER NOT NULL DEFAULT 0,
            lease TEXT NOT NULL DEFAULT '',
            lease_until TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            summary TEXT NOT NULL DEFAULT '',
            result_json TEXT NOT NULL DEFAULT '{}',
            report TEXT NOT NULL DEFAULT '',
            UNIQUE(research_id,fingerprint)
        );
        CREATE TABLE IF NOT EXISTS research_verification_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            verification_id INTEGER NOT NULL REFERENCES research_verifications(id),
            started_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS research_verification_queue_idx
            ON research_verifications(state,id);
    """)


def _valid_id(value):
    if type(value) is not int or value < 1:
        raise ValueError("검증 번호가 올바르지 않습니다.")
    return value


def _source_snapshot(store,research_id):
    job=research.get_job(store,research_id)
    if job["state"] not in ("completed","partial"):
        raise ValueError("원문 수집이 끝난 조사만 검토할 수 있습니다.")
    sources=[{
        "rank":item["rank"],
        "title":item["title"][:180],
        "url":item["url"][:2048],
        "domain":item["domain"][:253],
        "content_excerpt":item["content_excerpt"][:2400],
        "claimed_published_at":item["claimed_published_at"][:90],
        "checked_at":item["checked_at"],
        "source_status":item["state"]
    } for item in job["sources"] if item["state"]=="retrieved" and
           len(item["content_excerpt"])>=35][:4]
    if not sources:
        raise ValueError("실제로 수집한 원문이 없어 검증할 수 없습니다.")
    return job["query"],sources


def enqueue(store,research_id):
    research_id=_valid_id(research_id)
    query,sources=_source_snapshot(store,research_id)
    material=json.dumps([query,sources],ensure_ascii=False,sort_keys=True)
    fingerprint=sha256(material.encode("utf-8")).hexdigest()
    now=iso_now()
    with store.db:
        row=store.db.execute(
            "SELECT id FROM research_verifications WHERE research_id=? AND fingerprint=?",
            (research_id,fingerprint)).fetchone()
        if row:
            return get_job(store,row[0])
        if store.db.execute(
            "SELECT COUNT(*) FROM research_verifications WHERE state IN ('queued','running')"
        ).fetchone()[0]>=5:
            raise ValueError("진행 중인 검증이 많습니다.")
        id=store.db.execute(
            "INSERT INTO research_verifications(research_id,fingerprint,evidence_json,state,created_at,updated_at) "
            "VALUES(?,?,?,'queued',?,?)",
            (research_id,fingerprint,json.dumps(sources,ensure_ascii=False),now,now)
        ).lastrowid
    return get_job(store,id)


def get_job(store,raw_id):
    id=_valid_id(raw_id)
    row=store.db.execute(
        "SELECT id,research_id,state,attempt,created_at,updated_at,summary,result_json,report "
        "FROM research_verifications WHERE id=?",(id,)
    ).fetchone()
    if not row:
        raise ValueError("검증 기록을 찾을 수 없습니다.")
    item=dict(row)
    item["result"]=json.loads(item.pop("result_json"))
    return item


def status(store):
    count=dict(store.db.execute(
        "SELECT state,count(*) FROM research_verifications GROUP BY state"))
    items=[dict(row) for row in store.db.execute(
        "SELECT id,research_id,state,summary,created_at,updated_at "
        "FROM research_verifications ORDER BY id DESC LIMIT 8"
    )]
    used=store.db.execute(
        "SELECT COUNT(*) FROM research_verification_runs WHERE started_at>?",
        ((datetime.now(timezone.utc)-timedelta(hours=24)).isoformat(timespec="seconds"),)
    ).fetchone()[0]
    recent=get_job(store,items[0]["id"]) if items else None
    return {"counts":count,"items":items,"remaining":max(0,MAX_DAILY-used),
            "latest_result":recent}


def cancel(store,raw_id):
    id=_valid_id(raw_id)
    with store.db:
        return bool(store.db.execute(
            "UPDATE research_verifications SET state='cancelled',lease='',lease_until='',"
            "summary=?,updated_at=? WHERE id=? AND state IN ('queued','running')",
            ("사용자가 검증을 중단했습니다.",iso_now(),id)
        ).rowcount)


def _now():
    return datetime.now(timezone.utc)


def claim(store,now=None):
    now=now or _now()
    stamp=now.isoformat(timespec="seconds")
    with store.db:
        # Leases are not permanent; a crashed Mac may retry within the budget.
        store.db.execute(
            "UPDATE research_verifications SET state=CASE WHEN attempt>=? THEN 'failed' ELSE 'queued' END,"
            "lease='',lease_until='',updated_at=?,summary='이전 검증 실행이 중단됨' "
            "WHERE state='running' AND lease_until<=?",
            (MAX_ATTEMPTS,stamp,stamp)
        )
        if store.db.execute(
            "SELECT 1 FROM research_verifications WHERE state='running' LIMIT 1"
        ).fetchone():
            return None
        used=store.db.execute(
            "SELECT COUNT(*) FROM research_verification_runs WHERE started_at>?",
            ((now-timedelta(hours=24)).isoformat(timespec="seconds"),)
        ).fetchone()[0]
        if used>=MAX_DAILY:
            return None
        row=store.db.execute(
            "SELECT v.id,v.research_id,v.evidence_json,r.query "
            "FROM research_verifications v JOIN research_jobs r ON r.id=v.research_id "
            "WHERE v.state='queued' AND v.attempt<? ORDER BY v.id LIMIT 1",
            (MAX_ATTEMPTS,)
        ).fetchone()
        if row is None:return None
        token=uuid4().hex
        store.db.execute(
            "UPDATE research_verifications SET state='running',attempt=attempt+1,lease=?,"
            "lease_until=?,updated_at=?,summary=? WHERE id=?",
            (token,(now+timedelta(seconds=LEASE_SECONDS)).isoformat(timespec="seconds"),
             stamp,"로컬 Qwen에서 원문 비교 중",row["id"])
        )
        store.db.execute(
            "INSERT INTO research_verification_runs(verification_id,started_at) VALUES(?,?)",
            (row["id"],stamp)
        )
    return {"id":row["id"],"lease":token,"research_id":row["research_id"],
            "query":row["query"],"sources":json.loads(row["evidence_json"])}


def _normal(value):
    return " ".join(value.split())


def _date_status(raw):
    if not raw:
        return "발행일 미제공"
    try:
        dt=datetime.fromisoformat(raw.replace("Z","+00:00"))
    except (ValueError,TypeError):
        try:dt=parsedate_to_datetime(raw)
        except (ValueError,TypeError):return "발행일 형식 확인 불가"
    if dt.tzinfo is None:dt=dt.replace(tzinfo=timezone.utc)
    if dt>_now()+timedelta(days=1):
        return "미래 날짜 표시 — 확인 필요"
    return "출처가 주장한 날짜(독립 검증 아님)"


def assess(source):
    return {
        "rank":source["rank"],"url":source["url"],"domain":source["domain"],
        "source_status":source["source_status"],"checked_at":source["checked_at"],
        "claimed_published_at":source["claimed_published_at"],
        "date_assessment":_date_status(source["claimed_published_at"]),
        "publisher_identity":"독립 확인 안 됨",
    }


def _validated_model_output(raw,sources):
    if not isinstance(raw,str) or not 1<=len(raw)<=MAX_OUTPUT:
        raise ValueError("모델이 검토 결과를 반환하지 않았습니다.")
    try:data=json.loads(raw)
    except json.JSONDecodeError:raise ValueError("모델 응답이 JSON 형식이 아닙니다.") from None
    if not isinstance(data,dict) or not isinstance(data.get("claims"),list):
        raise ValueError("모델 주장 구조를 확인할 수 없습니다.")
    lookup={source["rank"]:source for source in sources}
    claims=[]
    rejected=0
    for candidate in data["claims"][:MAX_CLAIMS]:
        if not isinstance(candidate,dict) or not isinstance(candidate.get("evidence"),list):
            rejected+=1
            continue
        statement=candidate.get("statement")
        if not isinstance(statement,str) or not 4<=len(statement.strip())<=320:
            rejected+=1
            continue
        refs=[]
        seen=set()
        for raw_ref in candidate["evidence"][:MAX_EVIDENCE]:
            if not isinstance(raw_ref,dict):
                rejected+=1;continue
            rank=raw_ref.get("rank")
            quote=raw_ref.get("quote")
            stance=raw_ref.get("stance")
            source=lookup.get(rank) if type(rank) is int else None
            if not source or rank in seen or not isinstance(quote,str) or not 12<=len(quote)<=360 or stance not in (
                "supports","opposes","context"
            ):
                rejected+=1;continue
            # A model's citation is accepted ONLY if literal text is present
            # in that exact fetched excerpt. Claim truth remains unverified.
            if _normal(quote) not in _normal(source["content_excerpt"]):
                rejected+=1;continue
            refs.append({"rank":rank,"url":source["url"],"domain":source["domain"],
                         "quote":_normal(quote),"stance":stance})
            seen.add(rank)
        if not refs:
            if not candidate["evidence"]:
                rejected+=1  # a claim with no citations at all
            continue
        positions={x["stance"] for x in refs}
        distinct_domains=len({x["domain"] for x in refs})
        if "supports" in positions and "opposes" in positions:
            relation="possible_conflict_requires_review"
        elif distinct_domains>=2:
            relation="multiple_domains_independence_unverified"
        else:
            relation="single_domain_or_context_only"
        claims.append({"statement":statement.strip(),"evidence":refs,
                       "comparison":relation,"claim_status":"ai_proposed_quote_anchored_unverified"})
    interpretation=data.get("interpretation","")
    interpretation=(interpretation[:700] if isinstance(interpretation,str) and claims else "")
    questions=data.get("next_checks",[])
    questions=[x[:160] for x in questions[:3] if isinstance(x,str) and 5<=len(x)<=200] if isinstance(questions,list) else []
    return {"claims":claims,"rejected_citations":rejected,
            "interpretation":interpretation,
            "next_checks":questions,"source_assessments":[assess(x) for x in sources],
            "trust":"all_claims_are_unverified_even_if_quotes_match"}


def _render(verification,query,results):
    sources=results["source_assessments"]
    lines=["# DECHIVE RESEARCH / 교차 검토 기록","",
        f"원래 질문: {query}",
        f"연결된 조사: {verification['research_id']}번 / 검토: {verification['id']}번",
        "판정: 모델이 제시한 인용의 원문 존재 여부만 기계적으로 확인했습니다.",
        "인용이 존재해도 주장의 사실성, 출처의 신원, 출처 간 독립성은 인증되지 않습니다.",
        f"인용 연결 거부: {results['rejected_citations']}건","",
        "## 출처 정보와 날짜"]
    for item in sources:
        lines += [f"[{item['rank']}] {item['url']}",
                  f"원문 상태: {item['source_status']} · 조회: {item['checked_at']}",
                  f"표시 발행일: {item['claimed_published_at'] or '미제공'} · {item['date_assessment']}",
                  f"게시자 신원: {item['publisher_identity']}",""]
    lines.append("## 출처와 대조한 주장 제안")
    if not results["claims"]:
        lines.append("원문 발췌와 정확히 연결할 수 있는 주장을 확보하지 못했습니다. 사실 판단을 보류합니다.")
    for i,claim in enumerate(results["claims"],1):
        lines.extend([f"### 후보 {i} · AI가 추출한 주장(미검증)",
                      claim["statement"],f"출처 비교 상태: {claim['comparison']}"])
        for e in claim["evidence"]:
            lines += [f"- [{e['rank']}] {e['stance']} · {e['url']}",
                      "  원문 그대로의 인용: "+e["quote"]]
        lines.append("")
    lines+=["## AI 해석 — 검증 전 가설",
            results["interpretation"] if results["interpretation"] else
            "검증 가능한 인용이 부족하므로 AI 해석을 제공하지 않습니다.","",
            "## 다음에 확인할 사항"]
    lines += [f"- {q}" for q in results["next_checks"]] or ["- 공식 발표·원문·독립적인 근거를 추가로 검증하세요."]
    lines += ["", "외부 페이지 안의 지시문, 광고, 링크는 자비스의 실행 명령이 아닙니다."]
    return "\n".join(lines)[:16000]


def finish(store,raw_id,lease,outcome,raw_output="",now=None):
    id=_valid_id(raw_id)
    if not isinstance(lease,str) or len(lease)!=32 or outcome not in ("result","interrupted","failed"):
        raise ValueError("검토 실행 식별자가 잘못되었습니다.")
    now=now or _now()
    stamp=now.isoformat(timespec="seconds")
    with store.db:
        row=store.db.execute(
            "SELECT v.*,r.query FROM research_verifications v "
            "JOIN research_jobs r ON r.id=v.research_id "
            "WHERE v.id=? AND v.lease=? AND v.state='running' AND v.lease_until>?",
            (id,lease,stamp)
        ).fetchone()
        if not row:return False
        results={};report="";summary=""
        if outcome=="result":
            try:
                evidence=json.loads(row["evidence_json"])
                results=_validated_model_output(raw_output,evidence)
                state="draft" if results["claims"] else "insufficient"
                summary=(f"출처 인용 연결 {len(results['claims'])}개 · 거부 {results['rejected_citations']}건"
                         if results["claims"] else "인용 근거 부족 · 사실 판단 보류")
                report=_render(row,row["query"],results)
            except ValueError:
                outcome="failed"
        if outcome!="result":
            state="failed" if row["attempt"]>=MAX_ATTEMPTS else "queued"
            summary="검토 실행이 중단되었거나 모델 응답이 유효하지 않습니다."
        store.db.execute(
            "UPDATE research_verifications SET state=?,summary=?,report=?,result_json=?,"
            "lease='',lease_until='',updated_at=? WHERE id=?",
            (state,summary,report,json.dumps(results,ensure_ascii=False),stamp,id)
        )
    return True
