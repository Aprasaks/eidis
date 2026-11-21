"""Local, bounded continuity checks. No model, network, audio or tool execution."""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta, timezone

from .thinking import related_context

TASK_AGE = timedelta(days=3)
THOUGHT_AGE = timedelta(days=1)
THOUGHT_BATCH = 24
SCAN_INTERVAL = 60.0


def init_schema(db):
    db.executescript("""
        CREATE TABLE IF NOT EXISTS continuity_alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL CHECK(kind IN ('task','thought')),
            source_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            reason TEXT NOT NULL,
            evidence_json TEXT NOT NULL DEFAULT '[]',
            fingerprint TEXT NOT NULL,
            state TEXT NOT NULL CHECK(state IN ('open','acknowledged','resolved')),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(kind,source_id)
        );
        CREATE TABLE IF NOT EXISTS continuity_watch (
            thought_id INTEGER PRIMARY KEY,
            fingerprint TEXT NOT NULL,
            age_reported INTEGER NOT NULL DEFAULT 0,
            checked_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS continuity_meta (
            id INTEGER PRIMARY KEY CHECK(id=1),
            last_scan TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS continuity_open_idx
            ON continuity_alerts(state,updated_at DESC,id DESC);
    """)


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(",", ":")).encode()).hexdigest()


def stamp(now):
    return now.isoformat(timespec="seconds")


def is_old(value, now, age):
    try:
        parsed = datetime.fromisoformat(value)
        return parsed.tzinfo is not None and now - parsed >= age
    except (ValueError, TypeError):
        return False


def _alert(db, kind, source_id, title, reason, evidence, fingerprint, now):
    # Acknowledgement survives restarts and repeated scans of unchanged evidence.
    db.execute("""
        INSERT INTO continuity_alerts(kind,source_id,title,reason,evidence_json,
            fingerprint,state,created_at,updated_at)
        VALUES (?,?,?,?,?,?,'open',?,?)
        ON CONFLICT(kind,source_id) DO UPDATE SET
            title=excluded.title,reason=excluded.reason,
            evidence_json=excluded.evidence_json,fingerprint=excluded.fingerprint,
            state='open',updated_at=excluded.updated_at
        WHERE continuity_alerts.fingerprint<>excluded.fingerprint
           OR continuity_alerts.state='resolved'
    """, (kind, source_id, title[:220], reason, json.dumps(evidence, ensure_ascii=False),
          fingerprint, stamp(now), stamp(now)))


def scan(store, now=None):
    """Inspect only existing user-controlled records; never change their status."""
    now = now or datetime.now(timezone.utc)
    db = store.db
    with db:
        # Resolve task alerts once their original record is completed or removed.
        db.execute("""
            UPDATE continuity_alerts SET state='resolved',updated_at=?
            WHERE kind='task' AND state<>'resolved' AND NOT EXISTS (
                SELECT 1 FROM project_tasks t
                WHERE t.id=continuity_alerts.source_id AND t.status<>'done'
            )
        """, (stamp(now),))
        for row in db.execute("""
            SELECT t.id,t.title,t.status,t.updated_at,p.name AS project_name
            FROM project_tasks t JOIN projects p ON p.id=t.project_id
            WHERE t.status<>'done' ORDER BY t.id
        """).fetchall():
            old = is_old(row["updated_at"], now, TASK_AGE)
            if row["status"] != "blocked" and not old:
                db.execute("""UPDATE continuity_alerts SET state='resolved',updated_at=?
                    WHERE kind='task' AND source_id=? AND state<>'resolved'""",
                    (stamp(now), row["id"]))
                continue
            reason = ("작업 기록이 차단됨 상태입니다. 막힌 원인을 확인할 필요가 있습니다."
                      if row["status"] == "blocked" else
                      "작업 기록이 3일 이상 갱신되지 않았습니다. 실제 진행 여부를 확인해 주세요.")
            evidence = [{"kind": "project_task", "source_id": row["id"],
                         "source_status": row["status"], "recorded_at": row["updated_at"]}]
            _alert(db, "task", row["id"], row["project_name"]+" / "+row["title"],
                   reason, evidence, digest(dict(row)), now)

        # User review/rejection resolves an alert, but does not certify a claim.
        db.execute("""
            UPDATE continuity_alerts SET state='resolved',updated_at=?
            WHERE kind='thought' AND state<>'resolved' AND NOT EXISTS (
                SELECT 1 FROM thought_records t
                WHERE t.id=continuity_alerts.source_id AND t.status='hypothesis'
            )
        """, (stamp(now),))
        db.execute("""DELETE FROM continuity_watch WHERE NOT EXISTS (
            SELECT 1 FROM thought_records t
            WHERE t.id=continuity_watch.thought_id AND t.status='hypothesis')""")
        # Rotate bounded batches so a large archive doesn't delay interactive chat.
        rows = db.execute("""
            SELECT t.id,t.topic,t.hypothesis,t.updated_at,w.fingerprint AS prior,
                   COALESCE(w.age_reported,0) AS age_reported
            FROM thought_records t LEFT JOIN continuity_watch w ON w.thought_id=t.id
            WHERE t.status='hypothesis'
            ORDER BY COALESCE(w.checked_at,''),t.id LIMIT ?
        """, (THOUGHT_BATCH,)).fetchall()
        for row in rows:
            # Other AI hypotheses are excluded to avoid self-reinforcing feedback.
            matches = related_context(store, (row["topic"]+" "+row["hypothesis"])[:900],
                                      limit=5, include_thoughts=False)
            evidence = sorted(matches, key=lambda r: (r["kind"], r["source_id"]))
            fingerprint = digest(evidence)
            changed = row["prior"] is not None and row["prior"] != fingerprint
            age_due = not row["age_reported"] and is_old(row["updated_at"], now, THOUGHT_AGE)
            if changed or age_due:
                refs = [{k: r[k] for k in ("kind","source_id","source_status","recorded_at")}
                        for r in evidence]
                reason = ("관련 저장 자료의 검색 결과가 바뀌었습니다. 기존 가설을 다시 검토하세요."
                          if changed else
                          "저장한 가설이 24시간 이상 검증 전 상태입니다. 아직 결론으로 확정할 수 없습니다.")
                _alert(db, "thought", row["id"], row["topic"], reason, refs,
                       digest([fingerprint, row["updated_at"]]), now)
            db.execute("""
                INSERT INTO continuity_watch(thought_id,fingerprint,age_reported,checked_at)
                VALUES (?,?,?,?)
                ON CONFLICT(thought_id) DO UPDATE SET fingerprint=excluded.fingerprint,
                    age_reported=excluded.age_reported,checked_at=excluded.checked_at
            """, (row["id"],fingerprint,int(bool(row["age_reported"] or age_due)),stamp(now)))
        db.execute("""INSERT INTO continuity_meta(id,last_scan) VALUES (1,?)
            ON CONFLICT(id) DO UPDATE SET last_scan=excluded.last_scan""", (stamp(now),))


def snapshot(store, limit=20):
    limit = min(max(limit, 1), 50)
    db = store.db
    last = db.execute("SELECT last_scan FROM continuity_meta WHERE id=1").fetchone()
    count = db.execute("SELECT COUNT(*) FROM continuity_alerts WHERE state='open'").fetchone()[0]
    rows = db.execute("""SELECT id,kind,source_id,title,reason,evidence_json,updated_at
        FROM continuity_alerts WHERE state='open'
        ORDER BY updated_at DESC,id DESC LIMIT ?""", (limit,)).fetchall()
    items = []
    for row in rows:
        item = dict(row)
        item["evidence"] = json.loads(item.pop("evidence_json"))
        items.append(item)
    return {"last_scan": last[0] if last else None, "open_count": count, "items": items}


def acknowledge(store, alert_id):
    if type(alert_id) is not int or alert_id <= 0:
        raise ValueError("알림 번호를 확인해 주세요.")
    with store.db:
        result = store.db.execute("""UPDATE continuity_alerts
            SET state='acknowledged',updated_at=? WHERE id=? AND state='open'""",
            (stamp(datetime.now(timezone.utc)),alert_id))
    return result.rowcount == 1
