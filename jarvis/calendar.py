"""JARVIS-owned calendar records for the local Mac data store.

No Apple/Google Calendar dependency. All dates are UTC ISO 8601; changes are
explicit user actions; deletes leave tombstones for future sync.
The current Mac server stays bound to loopback, not accessible from the phone.
"""
from __future__ import annotations

import sqlite3
import uuid
from datetime import datetime, timezone


def schema(db: sqlite3.Connection) -> None:
    """Additive schema; preserve prior iPhone-compatible records when migrating.

    Older prototypes required end_at. SQLite cannot DROP NOT NULL in place, so
    rebuild only this calendar table inside one database transaction, retaining
    every record and deleted tombstone. Other JARVIS tables are untouched.
    """
    db.execute("""
        CREATE TABLE IF NOT EXISTS calendar_events (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            start_at TEXT NOT NULL,
            end_at TEXT,
            location TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            reminder_minutes INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            CHECK (reminder_minutes IS NULL OR reminder_minutes IN (0,10,30,60))
        )
    """)
    columns = db.execute("PRAGMA table_info(calendar_events)").fetchall()
    end_column = next((item for item in columns if item[1] == "end_at"), None)
    if not end_column:
        raise ValueError("calendar_events schema is invalid; stopped without deleting any records")
    if end_column[3] == 1:
        with db:
            db.execute("""
                CREATE TABLE calendar_events_nullable_v2 (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    start_at TEXT NOT NULL,
                    end_at TEXT,
                    location TEXT NOT NULL DEFAULT '',
                    notes TEXT NOT NULL DEFAULT '',
                    reminder_minutes INTEGER,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    deleted_at TEXT,
                    CHECK (reminder_minutes IS NULL OR reminder_minutes IN (0,10,30,60))
                )
            """)
            db.execute("""INSERT INTO calendar_events_nullable_v2
                (id,title,start_at,end_at,location,notes,reminder_minutes,created_at,updated_at,deleted_at)
                SELECT id,title,start_at,end_at,location,notes,reminder_minutes,created_at,updated_at,deleted_at
                FROM calendar_events""")
            db.execute("DROP TABLE calendar_events")
            db.execute("ALTER TABLE calendar_events_nullable_v2 RENAME TO calendar_events")
    db.execute("CREATE INDEX IF NOT EXISTS calendar_by_date_idx ON calendar_events(deleted_at,start_at)")


def _timestamp(raw: object, field: str) -> str:
    if not isinstance(raw, str) or len(raw) > 60:
        raise ValueError(field + ": ISO 8601 날짜가 필요합니다.")
    try:
        date = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if date.utcoffset() is None:
            raise ValueError("timezone missing")
        return date.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    except (TypeError, ValueError) as exc:
        raise ValueError(field + ": 시간대를 포함한 정확한 날짜가 필요합니다.") from exc


def _id(raw: object) -> str:
    if not isinstance(raw, str):
        raise ValueError("일정 ID 형식이 올바르지 않습니다.")
    try:
        return str(uuid.UUID(raw))
    except ValueError as exc:
        raise ValueError("일정 ID 형식이 올바르지 않습니다.") from exc


def _record(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"], "title": row["title"],
        "startAt": row["start_at"], "endAt": row["end_at"],
        "location": row["location"], "notes": row["notes"],
        "reminderMinutes": row["reminder_minutes"],
        "createdAt": row["created_at"], "updatedAt": row["updated_at"],
        "deletedAt": row["deleted_at"],
    }


def _validated(data: dict, update: bool) -> tuple:
    fields = {"id", "title", "startAt", "endAt", "location", "notes", "reminderMinutes"}
    if update:
        fields.add("expectedUpdatedAt")
    if not isinstance(data, dict) or not {"title", "startAt"}.issubset(data) or set(data) - fields:
        raise ValueError("일정 제목·시작이 필요하며, 종료는 미정으로 비울 수 있습니다.")
    if update and "id" not in data:
        raise ValueError("수정할 일정 ID가 필요합니다.")
    title, location, notes = data.get("title"), data.get("location", ""), data.get("notes", "")
    if not all(isinstance(x, str) for x in (title, location, notes)):
        raise ValueError("제목·장소·메모는 문자열이어야 합니다.")
    title, location, notes = title.strip(), location.strip(), notes.strip()
    if not 1 <= len(title) <= 120 or len(location) > 200 or len(notes) > 2000:
        raise ValueError("제목은 1~120자, 장소 200자, 메모 2000자 이하입니다.")
    start = _timestamp(data["startAt"], "시작")
    end = _timestamp(data["endAt"], "종료") if data.get("endAt") is not None else None
    if end is not None:
        duration = (datetime.fromisoformat(end.replace("Z", "+00:00")) -
                    datetime.fromisoformat(start.replace("Z", "+00:00"))).total_seconds()
        if not 0 < duration <= 604800:
            raise ValueError("종료는 시작 이후여야 하며 최대 7일까지 등록할 수 있습니다.")
    reminder = data.get("reminderMinutes")
    if reminder is not None and (type(reminder) is not int or reminder not in (0, 10, 30, 60)):
        raise ValueError("알림은 0·10·30·60분 중 하나여야 합니다.")
    event_id = _id(data["id"]) if "id" in data else str(uuid.uuid4())
    return event_id, title, start, end, location, notes, reminder


def listing(db: sqlite3.Connection, *, begin: str | None = None,
            finish: str | None = None, limit: int = 100) -> dict:
    if type(limit) is not int or not 1 <= limit <= 200:
        raise ValueError("조회 개수는 1~200 사이여야 합니다.")
    where = ["deleted_at IS NULL"]
    parameters = []
    if begin is not None:
        where.append("(end_at IS NULL OR end_at > ?)")
        parameters.append(_timestamp(begin, "조회 시작"))
    if finish is not None:
        where.append("start_at < ?")
        parameters.append(_timestamp(finish, "조회 종료"))
    parameters.append(limit)
    query = "SELECT * FROM calendar_events WHERE " + " AND ".join(where) + " ORDER BY start_at, id LIMIT ?"
    result = [_record(row) for row in db.execute(query, parameters).fetchall()]
    return {"items": result, "source": "JARVIS own local calendar", "sync": "not_connected"}


def create(db: sqlite3.Connection, data: dict) -> dict:
    event_id, title, start, end, location, notes, reminder = _validated(data, False)
    now = datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")
    try:
        with db:
            db.execute("""INSERT INTO calendar_events
                (id,title,start_at,end_at,location,notes,reminder_minutes,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?)""",
                (event_id, title, start, end, location, notes, reminder, now, now))
    except sqlite3.IntegrityError as exc:
        raise ValueError("이미 등록된 일정입니다. 중복 저장하지 않았습니다.") from exc
    return _record(db.execute("SELECT * FROM calendar_events WHERE id=?", (event_id,)).fetchone())


def update(db: sqlite3.Connection, data: dict) -> dict:
    event_id, title, start, end, location, notes, reminder = _validated(data, True)
    expected = data.get("expectedUpdatedAt")
    if expected is not None:
        _timestamp(expected, "수정 이력")  # retain exact server timestamp as concurrency token
    with db:
        row = db.execute("SELECT * FROM calendar_events WHERE id=? AND deleted_at IS NULL", (event_id,)).fetchone()
        if row is None:
            raise ValueError("수정할 일정이 없습니다.")
        if expected is not None and row["updated_at"] != expected:
            raise ValueError("일정이 다른 곳에서 수정됐습니다. 다시 조회해 주세요.")
        now = datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")
        db.execute("""UPDATE calendar_events SET title=?,start_at=?,end_at=?,location=?,notes=?,
                   reminder_minutes=?,updated_at=? WHERE id=? AND deleted_at IS NULL""",
                   (title, start, end, location, notes, reminder, now, event_id))
    return _record(db.execute("SELECT * FROM calendar_events WHERE id=?", (event_id,)).fetchone())


def delete(db: sqlite3.Connection, data: dict) -> dict:
    if not isinstance(data, dict) or set(data) - {"id", "expectedUpdatedAt"} or "id" not in data:
        raise ValueError("일정 삭제에는 ID만 지정할 수 있습니다.")
    event_id = _id(data["id"])
    expected = data.get("expectedUpdatedAt")
    if expected is not None:
        _timestamp(expected, "수정 이력")
    with db:
        row = db.execute("SELECT * FROM calendar_events WHERE id=? AND deleted_at IS NULL", (event_id,)).fetchone()
        if row is None:
            raise ValueError("삭제할 일정이 없습니다.")
        if expected is not None and row["updated_at"] != expected:
            raise ValueError("일정이 변경됐습니다. 다시 확인해 주세요.")
        now = datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")
        db.execute("UPDATE calendar_events SET deleted_at=?,updated_at=? WHERE id=?", (now, now, event_id))
    return {"deleted": True, "id": event_id, "deletedAt": now}


def sync_snapshot(db: sqlite3.Connection) -> list[dict]:
    """Complete bounded snapshot including tombstones; never silently truncate.

    Only called via localhost by the Mac app's encrypted, explicitly paired
    nearby-device transport. There is no LAN or public HTTP calendar port.
    """
    count = db.execute("SELECT COUNT(*) FROM calendar_events").fetchone()[0]
    if count > 2000:
        raise ValueError("일정이 2,000건을 초과해 전체 동기화를 중단했습니다.")
    return [_record(row) for row in db.execute(
        "SELECT * FROM calendar_events ORDER BY start_at, id")]


def sync_changes(db: sqlite3.Connection, payload: dict) -> dict:
    """Optimistic, idempotent per-record sync. Conflicts retain both copies.

    Client supplies last Mac version for updates/deletes. A missing version
    is permitted ONLY for a new ID. The Mac remains authoritative and never
    trusts client clock timestamps for ordering.
    """
    if not isinstance(payload, dict) or set(payload) != {"operations"} or not isinstance(payload["operations"], list):
        raise ValueError("동기화 작업 목록 형식이 올바르지 않습니다.")
    operations = payload["operations"]
    if len(operations) > 150:
        raise ValueError("한 번에 150건까지 동기화할 수 있습니다.")
    # Validate the ENTIRE batch before writing any row. Otherwise a later
    # malformed record could leave an earlier record committed despite a 400.
    seen: set[str] = set()
    prepared = []
    for op in operations:
        if not isinstance(op, dict) or set(op) != {"record", "baseVersion"} or not isinstance(op["record"], dict):
            raise ValueError("동기화 항목 형식이 올바르지 않습니다.")
        rec = op["record"]
        event_id = _id(rec.get("id"))
        if event_id in seen:
            raise ValueError("같은 일정 ID를 여러 번 보낼 수 없습니다.")
        seen.add(event_id)
        base = op["baseVersion"]
        if base is not None:
            _timestamp(base, "기존 수정 버전")
        if rec.get("deletedAt") is not None:
            _timestamp(rec["deletedAt"], "삭제 시간")
        else:
            fields = {key: rec[key] for key in ("id", "title", "startAt", "endAt", "location", "notes", "reminderMinutes") if key in rec}
            _validated(fields, False)
        prepared.append((event_id, rec, base))

    acknowledged: list[str] = []
    conflicts: list[dict] = []
    for event_id, rec, base in prepared:
        current = db.execute("SELECT * FROM calendar_events WHERE id=?", (event_id,)).fetchone()
        if current is not None and base != current["updated_at"]:
            conflicts.append({"id": event_id, "reason": "changed_on_mac"})
            continue
        if current is None and base is not None:
            conflicts.append({"id": event_id, "reason": "missing_on_mac"})
            continue
        if rec.get("deletedAt") is not None:
            if current is None:
                # Created and deleted on iPhone before first connection.
                acknowledged.append(event_id)
            elif current["deleted_at"] is not None:
                acknowledged.append(event_id)
            else:
                delete(db, {"id": event_id, "expectedUpdatedAt": current["updated_at"]})
                acknowledged.append(event_id)
            continue
        fields = {key: rec[key] for key in ("id", "title", "startAt", "endAt", "location", "notes", "reminderMinutes") if key in rec}
        if current is None:
            create(db, fields)
        elif current["deleted_at"] is not None:
            conflicts.append({"id": event_id, "reason": "deleted_on_mac"})
            continue
        else:
            fields["expectedUpdatedAt"] = current["updated_at"]
            update(db, fields)
        acknowledged.append(event_id)
    return {"acknowledged": acknowledged, "conflicts": conflicts,
            "records": sync_snapshot(db), "sync": "paired_nearby"}
