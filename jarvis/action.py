"""Fixed read-only workflows with durable DECHIVE execution receipts.

No model-generated commands, URLs, shell, or remote mutation. Worker returns
observations to the server thread; only that thread writes to the local ledger.
"""
from __future__ import annotations

from collections import Counter
from pathlib import Path
from queue import Empty, Queue
import json
import sqlite3
import threading

from .storage import iso_now

WORKFLOWS = {
    "project_report": ("projects",),
    "youtube_report": ("youtube",),
    "overview_report": ("projects", "youtube"),
}
MAX_PENDING = 8
MAX_PROJECTS = 40
MAX_REPORT_CHARS = 18000
LABELS = {"projects": "로컬 프로젝트", "youtube": "YouTube 읽기 전용 API"}


def init_schema(db):
    db.executescript("""
        CREATE TABLE IF NOT EXISTS action_jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workflow TEXT NOT NULL CHECK(workflow IN('project_report','youtube_report','overview_report')),
            state TEXT NOT NULL CHECK(state IN('queued','running','completed','partial','failed','cancelled')),
            requested_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            report TEXT NOT NULL DEFAULT '',
            summary TEXT NOT NULL DEFAULT '',
            evidence_json TEXT NOT NULL DEFAULT '[]'
        );
        CREATE INDEX IF NOT EXISTS action_queue_idx ON action_jobs(state,id);
    """)


def _id(value):
    if type(value) is not int or value < 1:
        raise ValueError("업무 번호를 확인해 주세요.")
    return value


def submit(store, workflow):
    if not isinstance(workflow, str) or workflow not in WORKFLOWS:
        raise ValueError("허용된 읽기 전용 보고서 업무가 아닙니다.")
    now = iso_now()
    with store.db:
        n = store.db.execute("SELECT COUNT(*) FROM action_jobs WHERE state IN('queued','running')").fetchone()[0]
        if n >= MAX_PENDING:
            raise ValueError("대기 중인 업무가 너무 많습니다.")
        cursor = store.db.execute("INSERT INTO action_jobs(workflow,state,requested_at,updated_at) VALUES(?,'queued',?,?)",
                                  (workflow, now, now))
    return get_job(store, cursor.lastrowid)


def get_job(store, job_id):
    job_id = _id(job_id)
    row = store.db.execute("SELECT * FROM action_jobs WHERE id=?", (job_id,)).fetchone()
    if row is None:
        raise ValueError("업무를 찾을 수 없습니다.")
    result = dict(row)
    result["evidence"] = json.loads(result.pop("evidence_json"))
    return result


def status(store):
    counts = dict(store.db.execute("SELECT state,COUNT(*) FROM action_jobs GROUP BY state"))
    rows = store.db.execute("SELECT id,workflow,state,requested_at,updated_at,summary FROM action_jobs ORDER BY id DESC LIMIT 12").fetchall()
    return {"counts": counts, "items": [dict(row) for row in rows]}


def cancel(store, job_id):
    job_id = _id(job_id)
    with store.db:
        return bool(store.db.execute("UPDATE action_jobs SET state='cancelled',updated_at=?,summary=? WHERE id=? AND state IN('queued','running')",
                                     (iso_now(), "사용자 중단 요청. 미완료 결과는 보고서로 저장하지 않음.", job_id)).rowcount)


def recover(store):
    # A lost process cannot assert that it finished. Do not silently rerun.
    with store.db:
        store.db.execute("UPDATE action_jobs SET state='failed',summary=?,updated_at=? WHERE state='running'",
                         ("이전 실행이 중단되었습니다. 새 업무로 다시 요청해 주세요.", iso_now()))


def _project_observation(path):
    # Consistent read-only transaction, never write project status.
    uri = Path(path).resolve().as_uri() + "?mode=ro"
    db = sqlite3.connect(uri, uri=True, timeout=3)
    db.row_factory = sqlite3.Row
    try:
        db.execute("BEGIN")
        count = db.execute("SELECT COUNT(*) FROM projects").fetchone()[0]
        totals = dict(db.execute("SELECT status,COUNT(*) FROM project_tasks GROUP BY status"))
        rows = db.execute("""
            SELECT p.id,p.name,p.updated_at,
              (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id=p.id) AS total,
              (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id=p.id AND t.status='done') AS done,
              (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id=p.id AND t.status='doing') AS doing,
              (SELECT COUNT(*) FROM project_tasks t WHERE t.project_id=p.id AND t.status='blocked') AS blocked
            FROM projects p ORDER BY p.updated_at DESC,p.id DESC LIMIT ?
        """, (MAX_PROJECTS,)).fetchall()
        alerts = db.execute("SELECT COUNT(*) FROM continuity_alerts WHERE state='open'").fetchone()[0]
        blocked = db.execute("""
            SELECT p.id AS project_id,t.id,p.name,t.title FROM project_tasks t JOIN projects p ON p.id=t.project_id
            WHERE t.status='blocked' ORDER BY t.updated_at DESC,t.id DESC LIMIT 12
        """).fetchall()
        return {"source":"local_sqlite","observed_at":iso_now(),"project_count":count,
                "task_count":sum(totals.values()),"task_counts":totals,
                "open_review_alerts":alerts,"projects":[dict(r) for r in rows],
                "blocked_tasks":[dict(r) for r in blocked],
                "project_detail_limit":MAX_PROJECTS,"blocked_detail_limit":12}
    finally:
        db.close()


def _youtube_observation(provider):
    data = provider.summary()
    if not isinstance(data,dict) or not data.get("channel_id") or not data.get("checked_at"):
        raise ValueError("invalid provider response")
    # Allowlist fields only; never store OAuth data or arbitrary payloads.
    out = {key:data.get(key) for key in (
        "channel_id","channel_title","subscriber_count","video_count","channel_views",
        "period_start","period_end","checked_at")}
    metrics=data.get("analytics")
    out["analytics"] = ({k:metrics.get(k) for k in ("views","estimated_minutes_watched","subscribers_gained")}
                        if isinstance(metrics,dict) else None)
    out["source"]="youtube_readonly_api"
    out["observed_at"]=data["checked_at"]
    out["analytics_available"]=out["analytics"] is not None
    return out


def _display(value):
    if value is None: return "미확인"
    # Names/titles are quoted data, not instructions.
    return str(value).replace("\n"," ").replace("\r"," ")[:250]


def build_report(workflow, observations):
    lines=["# DECHIVE 업무 보고서", "", "자료 조회 시각 기준의 관찰 결과입니다. 실제 업무 완료나 미래 성과를 보장하지 않습니다.", ""]
    summaries=[]
    good=0
    degraded=False
    for step, entry in zip(WORKFLOWS[workflow], observations):
        lines += ["## "+LABELS[step]]
        if entry.get("state") != "completed":
            lines += ["조회 실패 — 확인하지 못한 자료입니다.", ""]
            degraded=True
            continue
        good+=1
        data=entry["data"]
        lines += ["출처: "+data["source"]+" | 조회(UTC): "+_display(data["observed_at"])]
        if step=="projects":
            c=data["task_counts"]
            summary=f'프로젝트 {data["project_count"]}개, 작업 {data["task_count"]}건, 완료 기록 {c.get("done",0)}건, 확인 알림 {data["open_review_alerts"]}건'
            summaries.append(summary)
            lines += [summary, f'예정 {c.get("todo",0)} · 진행 {c.get("doing",0)} · 막힘 {c.get("blocked",0)}',
                      "확인 알림은 저장 기록 기준이며 실제 지연·누락을 단정하지 않습니다.", ""]
            for p in data["projects"]:
                lines.append(f'- [{p["id"]}] {_display(p["name"])}: 완료 {p["done"]}/{p["total"]}, 진행 {p["doing"]}, 막힘 {p["blocked"]}')
            if data["project_count"]>len(data["projects"]): lines.append("프로젝트 상세는 최대 40개만 표시했습니다.")
            for t in data["blocked_tasks"]:
                lines.append(f'- 막힘 기록 #{t["id"]}: {_display(t["name"])} / {_display(t["title"])}')
            if c.get("blocked",0)>len(data["blocked_tasks"]): lines.append("막힘 작업 상세는 최대 12건만 표시했습니다.")
        else:
            summary=f'YouTube {_display(data["channel_title"])} 채널: 구독자 {_display(data["subscriber_count"])}, 영상 {_display(data["video_count"])}개'
            summaries.append(summary)
            lines += [summary, "누적 조회수 "+_display(data["channel_views"]),
                      "분석 기간: "+_display(data["period_start"])+" ~ "+_display(data["period_end"])]
            if data["analytics_available"]:
                a=data["analytics"]
                lines += ["기간 조회수 "+_display(a["views"]), "시청 시간(분) "+_display(a["estimated_minutes_watched"]),
                          "기간 신규 구독자 "+_display(a["subscribers_gained"])]
            else:
                lines.append("기간 분석 데이터 미확인 — 채널 기본 통계만 조회됨.")
                degraded=True
        lines.append("")
    state="failed" if good==0 else ("partial" if degraded else "completed")
    summary=" / ".join(summaries) or "자료 조회 실패."
    if state=="partial": summary+=" / 일부 자료 미확인"
    return state,summary[:1200],"\n".join(lines)[:MAX_REPORT_CHARS]


class ActionRunner:
    """Exactly one daemon worker. Only explicit queue submissions trigger work."""
    def __init__(self, store, youtube):
        self.store=store
        self.youtube=youtube
        self.active=None
        self.results=Queue()
        recover(store)

    def _checkpoint(self, job_id, workflow, observations):
        # A cancelled job is never resurrected by a late provider response.
        state,summary,report=build_report(workflow,observations)
        complete=len(observations)==len(WORKFLOWS[workflow])
        with self.store.db:
            changed=self.store.db.execute("""
                UPDATE action_jobs SET state=?,summary=?,report=?,evidence_json=?,updated_at=?
                WHERE id=? AND state='running'
            """, (state if complete else "running", summary if complete else f"자료 조회 {len(observations)}/{len(WORKFLOWS[workflow])}",
                  report if complete else "",json.dumps(observations,ensure_ascii=False),iso_now(),job_id)).rowcount
        return bool(changed)

    def _worker(self, job_id, workflow, stop):
        observations=[]
        for step in WORKFLOWS[workflow]:
            if stop.is_set(): break
            try:
                data=_project_observation(self.store.path) if step=="projects" else _youtube_observation(self.youtube)
                entry={"step":step,"state":"completed","data":data}
            except Exception:
                entry={"step":step,"state":"failed","observed_at":iso_now(),"reason":"source_unavailable"}
            observations.append(entry)
            if stop.is_set(): break
            self.results.put((job_id,workflow,list(observations),False))
        self.results.put((job_id,workflow,None,True))

    def tick(self):
        if self.active:
            job_id,stop=self.active
            row=self.store.db.execute("SELECT state FROM action_jobs WHERE id=?",(job_id,)).fetchone()
            if row is None or row[0]=="cancelled": stop.set()
        while True:
            try: job_id,workflow,observations,ended=self.results.get_nowait()
            except Empty: break
            if ended:
                if self.active and self.active[0]==job_id:
                    with self.store.db:
                        self.store.db.execute("UPDATE action_jobs SET state='failed',summary=?,updated_at=? WHERE id=? AND state='running'",
                                              ("실행이 중단되었습니다.",iso_now(),job_id))
                    self.active=None
            elif observations is not None:
                self._checkpoint(job_id,workflow,observations)
        if self.active: return
        row=self.store.db.execute("SELECT id,workflow FROM action_jobs WHERE state='queued' ORDER BY id LIMIT 1").fetchone()
        if row is None: return
        job_id,workflow=row
        with self.store.db:
            self.store.db.execute("UPDATE action_jobs SET state='running',updated_at=?,summary=? WHERE id=? AND state='queued'",
                                  (iso_now(),"허용된 자료 조회 중",job_id))
        stop=threading.Event()
        self.active=(job_id,stop)
        threading.Thread(target=self._worker,args=(job_id,workflow,stop),daemon=True,name="dechive-action").start()
