"""Local, opt-in memory store. Uses only the Python standard library."""
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class MemoryStore:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(path), check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA busy_timeout=5000")
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS memories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                content TEXT NOT NULL,
                project TEXT NOT NULL DEFAULT 'general',
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS activity (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category TEXT NOT NULL,
                result TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
        """)
        self.db.commit()

    def count_memories(self) -> int:
        return self.db.execute("SELECT COUNT(*) FROM memories").fetchone()[0]

    def add_memory(self, content: str, project: str = "general") -> dict:
        content, project = content.strip(), project.strip() or "general"
        if not content or len(content) > 2000 or len(project) > 80:
            raise ValueError("기억은 1~2000자, 프로젝트 이름은 80자 이하로 입력해 주세요.")
        with self.db:
            cursor = self.db.execute(
                "INSERT INTO memories (content, project, created_at) VALUES (?, ?, ?)",
                (content, project, iso_now()),
            )
        return {"id": cursor.lastrowid, "content": content, "project": project}

    def recent_memories(self, limit: int = 8) -> list[dict]:
        limit = max(1, min(50, int(limit)))
        return [dict(row) for row in self.db.execute(
            "SELECT id, content, project, created_at FROM memories ORDER BY id DESC LIMIT ?", (limit,)
        )]

    def record_event(self, category: str, result: str) -> None:
        """Do NOT save raw transcripts by default. Only event type and result."""
        with self.db:
            self.db.execute("INSERT INTO activity (category, result, created_at) VALUES (?, ?, ?)",
                            (category[:80], result[:80], iso_now()))

    def recent_activity(self, limit: int = 12) -> list[dict]:
        return [dict(row) for row in self.db.execute(
            "SELECT category, result, created_at FROM activity ORDER BY id DESC LIMIT ?",
            (max(1, min(50, int(limit))),)
        )]

    def close(self):
        self.db.close()
