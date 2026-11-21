"""DECHIVE 1.2: bounded study queue. Local drafts, never executable plans."""
from __future__ import annotations
from datetime import datetime, timedelta, timezone
import json
import uuid

from .thinking import related_context
from .continuity import digest, stamp

DAILY_LIMIT = 3
LEASE_SECONDS = 150
MAX_ATTEMPTS = 2
MAX_ACTIVE = 24


def utcnow():
    return datetime.now(timezone.utc)


def init_schema(db):
    db.executescript("""
        CREATE TABLE IF NOT EXISTS study_topics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            topic TEXT NOT NULL,
            premise TEXT NOT NULL,
            created_at TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1 CHECK(active IN(0,1)),
            last_fingerprint TEXT NOT NULL DEFAULT '',
            checked_at TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS study_jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            topic_id INTEGER NOT NULL REFERENCES study_topics(id),
            fingerprint TEXT NOT NULL,
            evidence_json TEXT NOT NULL,
            state TEXT NOT NULL CHECK(state IN('queued','running','draft','failed','cancelled')),
            attempts INTEGER NOT NULL DEFAULT 0,
            lease TEXT NOT NULL DEFAULT '',
            lease_until TEXT NOT NULL DEFAULT '',
            available_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            result TEXT NOT NULL DEFAULT '',
            UNIQUE(topic_id,fingerprint)
        );
        CREATE TABLE IF NOT EXISTS study_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job_id INTEGER NOT NULL REFERENCES study_jobs(id),
            started_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS study_settings (
            id INTEGER PRIMARY KEY CHECK(id=1),
            enabled INTEGER NOT NULL CHECK(enabled IN(0,1))
        );
        INSERT OR IGNORE INTO study_settings(id,enabled) VALUES (1,1);
        CREATE INDEX IF NOT EXISTS study_queue_idx ON study_jobs(state,available_at,id);
    """)


def enabled(store):
    return bool(store.db.execute("SELECT enabled FROM study_settings WHERE id=1").fetchone()[0])


def set_enabled(store, value):
    if type(value) is not bool:
        raise ValueError("자동 사고 허용 여부가 필요합니다.")
    with store.db:
        store.db.execute("UPDATE study_settings SET enabled=? WHERE id=1", (int(value),))
    return value


def create_topic(store, topic, premise=""):
    topic = store._thought_text(topic, "검토 주제", 300)
    if not isinstance(premise, str):
        raise ValueError("이전 의견을 확인해 주세요.")
    premise = store._thought_text(premise, "이전 의견", 1500) if premise.strip() else ""
    db = store.db
    with db:
        row = db.execute("SELECT id FROM study_topics WHERE active=1 AND topic=? AND premise=?",
                         (topic, premise)).fetchone()
        if row:
            return row[0]
        if db.execute("SELECT count(*) FROM study_topics WHERE active=1").fetchone()[0] >= MAX_ACTIVE:
            raise ValueError("자동 검토 주제는 최대 24개입니다. 먼저 불필요한 주제를 중단해 주세요.")
        return db.execute("INSERT INTO study_topics(topic,premise,created_at) VALUES(?,?,?)",
                          (topic,premise,stamp(utcnow()))).lastrowid


def stop_topic(store, topic_id):
    if type(topic_id) is not int or topic_id <= 0:
        raise ValueError("검토 주제 번호를 확인해 주세요.")
    with store.db:
        n = store.db.execute("UPDATE study_topics SET active=0 WHERE id=? AND active=1",
                             (topic_id,)).rowcount
        store.db.execute("""UPDATE study_jobs SET state='cancelled',lease='',lease_until='',updated_at=?
            WHERE topic_id=? AND state IN('queued','running')""", (stamp(utcnow()),topic_id))
    return bool(n)


def _evidence(store, topic):
    # Keep only local user-saved/project records. AI output cannot become evidence.
    candidates = related_context(store, topic[:900], limit=6, include_thoughts=False)
    return sorted([r for r in candidates if r["source_status"] in
                   ("user_supplied","user_saved","local_project_record")],
                  key=lambda r: (r["kind"],r["source_id"]))


def schedule(store, now=None):
    """Produce at most one job per source revision per explicit study topic."""
    now = now or utcnow()
    db = store.db
    if not enabled(store):
        return
    with db:
        rows = db.execute("SELECT * FROM study_topics WHERE active=1 ORDER BY checked_at,id").fetchall()
        for row in rows:
            evidence = _evidence(store,row["topic"])
            fingerprint = digest([row["topic"],row["premise"],evidence])
            if row["last_fingerprint"] != fingerprint:
                # A newer revision supersedes a queued (not completed) old job.
                db.execute("""UPDATE study_jobs SET state='cancelled',updated_at=?
                    WHERE topic_id=? AND state='queued' AND fingerprint<>?""",
                           (stamp(now),row["id"],fingerprint))
                db.execute("""INSERT INTO study_jobs
                    (topic_id,fingerprint,evidence_json,state,available_at,created_at,updated_at)
                    VALUES(?,?,?,'queued',?,?,?)
                    ON CONFLICT(topic_id,fingerprint) DO UPDATE SET
                        state='queued',available_at=excluded.available_at,updated_at=excluded.updated_at
                    WHERE study_jobs.state='cancelled' AND study_jobs.attempts<?""",
                           (row["id"],fingerprint,json.dumps(evidence,ensure_ascii=False),
                            stamp(now),stamp(now),stamp(now),MAX_ATTEMPTS))
            db.execute("UPDATE study_topics SET last_fingerprint=?,checked_at=? WHERE id=?",
                       (fingerprint,stamp(now),row["id"]))


def _recover(db, now):
    db.execute("""UPDATE study_jobs SET state='cancelled',lease='',lease_until='',updated_at=?
        WHERE state IN('queued','running') AND (state='queued' OR lease_until<=?) AND NOT EXISTS (
        SELECT 1 FROM study_topics t WHERE t.id=study_jobs.topic_id AND t.active=1
          AND t.last_fingerprint=study_jobs.fingerprint)""",(stamp(now),stamp(now)))
    db.execute("""UPDATE study_jobs SET state=CASE WHEN attempts>=? THEN 'failed' ELSE 'queued' END,
        lease='',lease_until='',available_at=?,updated_at=?
        WHERE state='running' AND lease_until<=?""",
        (MAX_ATTEMPTS,stamp(now),stamp(now),stamp(now)))


def claim(store, now=None):
    now = now or utcnow()
    db = store.db
    with db:
        _recover(db, now)
        if not enabled(store):
            return None
        if db.execute("SELECT 1 FROM study_jobs WHERE state='running' LIMIT 1").fetchone():
            return None
        if db.execute("SELECT count(*) FROM study_runs WHERE started_at>?",
                      (stamp(now-timedelta(hours=24)),)).fetchone()[0] >= DAILY_LIMIT:
            return None
        row = db.execute("""SELECT j.*,t.topic,t.premise FROM study_jobs j
            JOIN study_topics t ON t.id=j.topic_id
            WHERE j.state='queued' AND j.available_at<=? AND t.active=1
                AND j.fingerprint=t.last_fingerprint AND j.attempts<?
            ORDER BY j.id LIMIT 1""",(stamp(now),MAX_ATTEMPTS)).fetchone()
        if row is None:
            return None
        lease = uuid.uuid4().hex
        db.execute("""UPDATE study_jobs SET state='running',attempts=attempts+1,lease=?,
            lease_until=?,updated_at=? WHERE id=?""",
                   (lease,stamp(now+timedelta(seconds=LEASE_SECONDS)),stamp(now),row["id"]))
        db.execute("INSERT INTO study_runs(job_id,started_at) VALUES(?,?)",(row["id"],stamp(now)))
        return {"id":row["id"],"lease":lease,"topic":row["topic"],"premise":row["premise"],
                "evidence":json.loads(row["evidence_json"])}


def finish(store, job_id, lease, outcome, result="", now=None):
    now = now or utcnow()
    if type(job_id) is not int or not isinstance(lease,str) or len(lease)!=32:
        raise ValueError("실행 번호가 잘못되었습니다.")
    if outcome not in ("draft","interrupted","failed"):
        raise ValueError("유효하지 않은 사고 결과입니다.")
    if outcome=="draft":
        result=store._thought_text(result,"검토 초안",2000)
    else:
        result=""
    db=store.db
    with db:
        row=db.execute("""SELECT j.*,t.active,t.last_fingerprint FROM study_jobs j
            JOIN study_topics t ON t.id=j.topic_id WHERE j.id=? AND j.lease=?
            AND j.state='running' AND j.lease_until>?""",
            (job_id,lease,stamp(now))).fetchone()
        if not row:
            return False
        if not row["active"] or row["fingerprint"]!=row["last_fingerprint"]:
            state="cancelled";result=""
        elif outcome=="draft" and enabled(store):
            state="draft"
        else:
            result=""
            state="queued" if row["attempts"]<MAX_ATTEMPTS else "failed"
        db.execute("""UPDATE study_jobs SET state=?,result=?,lease='',lease_until='',
            available_at=?,updated_at=? WHERE id=?""",
            (state,result,stamp(now+timedelta(minutes=5)),stamp(now),job_id))
    return True


def status(store):
    db=store.db
    topics=[dict(r) for r in db.execute("""SELECT id,topic,active,checked_at FROM study_topics
        WHERE active=1 ORDER BY id DESC LIMIT 24""")]
    counts={r[0]:r[1] for r in db.execute("SELECT state,count(*) FROM study_jobs GROUP BY state")}
    latest=[dict(r) for r in db.execute("""SELECT j.id,j.topic_id,t.topic,j.state,j.updated_at
        FROM study_jobs j JOIN study_topics t ON t.id=j.topic_id
        WHERE j.state='draft' AND t.active=1 ORDER BY j.id DESC LIMIT 5""")]
    used=db.execute("SELECT count(*) FROM study_runs WHERE started_at>?",
                    (stamp(utcnow()-timedelta(hours=24)),)).fetchone()[0]
    draft_count = db.execute("""SELECT count(*) FROM study_jobs j JOIN study_topics t
        ON t.id=j.topic_id WHERE j.state='draft' AND t.active=1""").fetchone()[0]
    return {"enabled":enabled(store),"topics":topics,"counts":counts,"drafts":latest,"draft_count":draft_count,
            "remaining":max(0,DAILY_LIMIT-used)}


def get_draft(store, job_id):
    if type(job_id) is not int or job_id<=0:
        raise ValueError("초안 번호를 확인해 주세요.")
    row=store.db.execute("""SELECT j.id,j.topic_id,t.topic,j.state,j.result,j.evidence_json,j.updated_at
        FROM study_jobs j JOIN study_topics t ON t.id=j.topic_id WHERE j.id=? AND j.state='draft'""",
        (job_id,)).fetchone()
    if row is None:
        raise ValueError("완성된 검토 초안을 찾을 수 없습니다.")
    out=dict(row)
    out["evidence"]=json.loads(out.pop("evidence_json"))
    out["source_status"]="ai_generated_unverified"
    return out
