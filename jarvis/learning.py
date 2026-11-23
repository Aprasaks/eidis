"""Opt-in local learning memory: reviewed candidates, never automatic facts.

Only a short source excerpt and extracted candidate are persisted; no audio,
assistant response, full chat transcript, network provider or training job.
"""
from __future__ import annotations

import hashlib
import re
from .storage import iso_now

CATEGORIES = frozenset({
    "identity", "communication", "working_style", "values", "goals", "project",
})
LABELS = {
    "identity": "사용자 정체성",
    "communication": "대화 방식 말투",
    "working_style": "작업 방식",
    "values": "가치관 기준",
    "goals": "목표",
    "project": "프로젝트 결정",
}
SECRET_WORDS = (
    "비밀번호", "패스워드", "주민번호", "주민등록", "계좌번호", "카드번호",
    "인증번호", "일회용 비밀번호", "otp", "password", "api key", "api키",
    "secret key", "access token", "private key", "bearer ",
)
SECRET_PATTERNS = (
    r"sk-[a-zA-Z0-9_-]{20,}", r"gh[pousr]_[a-zA-Z0-9_]{20,}",
    r"AKIA[0-9A-Z]{16}", r"[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}",
    r"(?<!\d)01[016789][- ]?\d{3,4}[- ]?\d{4}(?!\d)",
    r"\b\d{6}[- ]?[1-4]\d{6}\b",
)


def safe_text(value: object, maximum: int, minimum: int = 1) -> str:
    if not isinstance(value, str):
        raise ValueError("기억은 문자열이어야 합니다.")
    clean = " ".join(value.strip().split())
    if not minimum <= len(clean) <= maximum:
        raise ValueError("기억 내용의 길이가 허용 범위를 벗어났습니다.")
    lowered = clean.lower()
    if any(term in lowered for term in SECRET_WORDS) or any(
        re.search(pattern, clean) for pattern in SECRET_PATTERNS
    ):
        raise ValueError("비밀정보·연락처는 자동 학습 기억에 저장하지 않습니다.")
    return clean


def init_schema(db) -> None:
    db.execute("""
        CREATE TABLE IF NOT EXISTS learning_settings (
            id INTEGER PRIMARY KEY CHECK(id=1),
            enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0,1))
        )
    """)
    db.execute("INSERT OR IGNORE INTO learning_settings(id,enabled) VALUES (1,0)")
    db.execute("""
        CREATE TABLE IF NOT EXISTS learned_memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL
                CHECK(category IN ('identity','communication','working_style',
                                   'values','goals','project')),
            content TEXT NOT NULL,
            source_excerpt TEXT NOT NULL,
            source_status TEXT NOT NULL DEFAULT 'ai_extracted_pending'
                CHECK(source_status IN ('ai_extracted_pending','user_approved','user_corrected')),
            status TEXT NOT NULL DEFAULT 'pending'
                CHECK(status IN ('pending','approved','rejected')),
            fingerprint TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)
    db.execute("CREATE INDEX IF NOT EXISTS learned_memories_status_idx ON learned_memories(status,id DESC)")
    db.execute("""
        CREATE TABLE IF NOT EXISTS learned_memory_revisions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            memory_id INTEGER NOT NULL REFERENCES learned_memories(id) ON DELETE CASCADE,
            old_content TEXT NOT NULL,
            new_content TEXT NOT NULL,
            changed_at TEXT NOT NULL
        )
    """)
    db.commit()


def enabled(store) -> bool:
    return bool(store.db.execute("SELECT enabled FROM learning_settings WHERE id=1").fetchone()[0])


def set_enabled(store, value: object) -> bool:
    if type(value) is not bool:
        raise ValueError("학습 사용 여부는 true/false로 지정해야 합니다.")
    with store.db:
        store.db.execute("UPDATE learning_settings SET enabled=? WHERE id=1", (int(value),))
    return value


def summary(store) -> dict:
    rows = store.db.execute("""
        SELECT id,category,content,source_excerpt,source_status,status,created_at,updated_at
        FROM learned_memories WHERE status IN ('pending','approved')
        ORDER BY id DESC LIMIT 80
    """).fetchall()
    return {
        "enabled": enabled(store),
        "pending": [dict(row) for row in rows if row["status"] == "pending"][:12],
        "approved": [dict(row) for row in rows if row["status"] == "approved"][:20],
        "pending_count": store.db.execute(
            "SELECT COUNT(*) FROM learned_memories WHERE status='pending'").fetchone()[0],
        "approved_count": store.db.execute(
            "SELECT COUNT(*) FROM learned_memories WHERE status='approved'").fetchone()[0],
    }


def propose(store, category: object, content: object, source_excerpt: object) -> dict:
    # Even direct user statements are only *candidates* when a model extracted them.
    if not enabled(store):
        raise ValueError("사용자가 대화 학습 기능을 켜지 않았습니다.")
    if not isinstance(category, str) or category not in CATEGORIES:
        raise ValueError("기억 분류가 올바르지 않습니다.")
    memory = safe_text(content, 350, 6)
    excerpt = safe_text(source_excerpt, 500, 6)
    if len(memory) > len(excerpt) * 2 + 60:
        raise ValueError("원본 발언보다 지나치게 긴 기억 추론입니다.")
    fingerprint = hashlib.sha256((category + "\n" + memory).encode("utf-8")).hexdigest()
    now = iso_now()
    with store.db:
        store.db.execute("""
            INSERT OR IGNORE INTO learned_memories (
                category,content,source_excerpt,fingerprint,created_at,updated_at
            ) VALUES(?,?,?,?,?,?)
        """, (category, memory, excerpt, fingerprint, now, now))
    row = store.db.execute(
        "SELECT id,category,content,source_status,status FROM learned_memories WHERE fingerprint=?",
        (fingerprint,)
    ).fetchone()
    return dict(row)


def _row(store, memory_id: object):
    if type(memory_id) is not int or memory_id < 1:
        raise ValueError("기억 번호가 올바르지 않습니다.")
    row = store.db.execute(
        "SELECT id,category,content,status FROM learned_memories WHERE id=?", (memory_id,)
    ).fetchone()
    if row is None:
        raise ValueError("기억 번호를 찾을 수 없습니다.")
    return row


def review(store, memory_id: object, action: object) -> dict:
    row = _row(store, memory_id)
    if action not in ("approve", "reject") or row["status"] != "pending":
        raise ValueError("검토 대기 중인 기억만 승인하거나 거절할 수 있습니다.")
    new_status = "approved" if action == "approve" else "rejected"
    with store.db:
        store.db.execute("""
            UPDATE learned_memories SET status=?,source_status=?,updated_at=? WHERE id=?
        """, (new_status,
              "user_approved" if action == "approve" else "ai_extracted_pending",
              iso_now(), memory_id))
    return {"id": memory_id, "status": new_status}


def correct(store, memory_id: object, content: object) -> dict:
    row = _row(store, memory_id)
    if row["status"] != "approved":
        raise ValueError("승인된 기억만 수정할 수 있습니다.")
    revised = safe_text(content, 350, 6)
    with store.db:
        store.db.execute("""
            INSERT INTO learned_memory_revisions(memory_id,old_content,new_content,changed_at)
            VALUES (?,?,?,?)
        """, (memory_id, row["content"], revised, iso_now()))
        store.db.execute("""
            UPDATE learned_memories SET content=?,source_status='user_corrected',
                updated_at=? WHERE id=?
        """, (revised, iso_now(), memory_id))
    return {"id": memory_id, "status": "approved", "content": revised}


def forget(store, memory_id: object) -> dict:
    _row(store, memory_id)
    # Actually erase the contents and their revisions. Do not retain tombstones.
    with store.db:
        store.db.execute("DELETE FROM learned_memories WHERE id=?", (memory_id,))
    return {"deleted": True, "id": memory_id}
