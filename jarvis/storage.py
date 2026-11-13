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
        self.db.execute("PRAGMA foreign_keys=ON")
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
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS projects (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL COLLATE NOCASE UNIQUE,
                goal TEXT NOT NULL DEFAULT '',
                repo_full_name TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS project_tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id INTEGER NOT NULL REFERENCES projects(id),
                title TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'todo'
                    CHECK(status IN ('todo','doing','blocked','done')),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS project_changes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id INTEGER NOT NULL,
                task_id INTEGER NOT NULL,
                old_status TEXT NOT NULL,
                new_status TEXT NOT NULL,
                actor TEXT NOT NULL DEFAULT 'user',
                changed_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS project_checks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id INTEGER NOT NULL REFERENCES projects(id),
                provider TEXT NOT NULL CHECK(provider = 'github'),
                repository TEXT NOT NULL,
                branch TEXT NOT NULL,
                head_sha TEXT NOT NULL,
                workflow_state TEXT NOT NULL,
                workflow_conclusion TEXT NOT NULL,
                workflow_url TEXT NOT NULL DEFAULT '',
                checked_at TEXT NOT NULL
            );
        """)
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS tool_executions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tool_name TEXT NOT NULL,
                project_id INTEGER NOT NULL REFERENCES projects(id),
                permission TEXT NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('started','completed','failed')),
                outcome TEXT NOT NULL DEFAULT '',
                head_sha TEXT NOT NULL DEFAULT '',
                requested_at TEXT NOT NULL,
                completed_at TEXT NOT NULL DEFAULT ''
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

    def search_memories(self, query: str, limit: int = 5) -> list[dict]:
        """Search explicitly saved notes. No automatic transcript indexing."""
        if not isinstance(query, str) or not 1 <= len(query.strip()) <= 120:
            raise ValueError("검색어를 1~120자로 입력해 주세요.")
        # Treat SQL LIKE wildcards as literal user characters.
        value = query.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        size = max(1, min(10, int(limit)))
        return [dict(row) for row in self.db.execute(
            "SELECT id, content, project, created_at FROM memories "
            "WHERE content LIKE ? ESCAPE '\\' OR project LIKE ? ESCAPE '\\' "
            "ORDER BY id DESC LIMIT ?",
            (f"%{value}%", f"%{value}%", size),
        )]

    def record_event(self, category: str, result: str) -> None:
        """Do NOT save raw transcripts by default. Only event type and result."""
        with self.db:
            self.db.execute("INSERT INTO activity (category, result, created_at) VALUES (?, ?, ?)",
                            (category[:80], result[:80], iso_now()))

    def recent_activity(self, limit: int = 12) -> list[dict]:
        return [dict(row) for row in self.db.execute(
            "SELECT id, category, result, created_at FROM activity ORDER BY id DESC LIMIT ?",
            (max(1, min(50, int(limit))),)
        )]


    @staticmethod
    def _required_text(value: object, *, field: str, maximum: int) -> str:
        if not isinstance(value, str) or not 1 <= len(value.strip()) <= maximum:
            raise ValueError(f"{field}은(는) 1~{maximum}자로 입력해 주세요.")
        return value.strip()

    @staticmethod
    def _valid_id(value: object) -> int:
        if type(value) is not int or not 1 <= value <= 2_147_483_647:
            raise ValueError("식별 번호가 올바르지 않습니다.")
        return value

    def create_project(self, name: object, goal: object = "", repo_full_name: object = "") -> dict:
        from .projects import validate_repo
        name = self._required_text(name, field="프로젝트 이름", maximum=80)
        if not isinstance(goal, str) or len(goal) > 500:
            raise ValueError("프로젝트 목표는 500자 이하로 입력해 주세요.")
        repo_full_name = validate_repo(repo_full_name, allow_empty=True)
        now = iso_now()
        try:
            with self.db:
                cursor = self.db.execute(
                    "INSERT INTO projects(name,goal,repo_full_name,created_at,updated_at) "
                    "VALUES (?,?,?,?,?)", (name,goal.strip(),repo_full_name,now,now)
                )
        except sqlite3.IntegrityError as exc:
            raise ValueError("같은 이름의 프로젝트가 이미 있습니다.") from exc
        return self.get_project(cursor.lastrowid)

    def _project_row(self, project_id: object) -> dict:
        project_id = self._valid_id(project_id)
        row = self.db.execute(
            "SELECT id,name,goal,repo_full_name,created_at,updated_at "
            "FROM projects WHERE id=?", (project_id,)
        ).fetchone()
        if row is None:
            raise ValueError("프로젝트를 찾을 수 없습니다.")
        return dict(row)

    def get_project(self, project_id: object) -> dict:
        project = self._project_row(project_id)
        rows = self.db.execute(
            "SELECT id,title,status,created_at,updated_at FROM project_tasks "
            "WHERE project_id=? ORDER BY id", (project["id"],)
        ).fetchall()
        project["tasks"] = [dict(row) for row in rows]
        row = self.db.execute(
            "SELECT provider,repository,branch,head_sha,workflow_state,"
            "workflow_conclusion,workflow_url,checked_at FROM project_checks "
            "WHERE project_id=? ORDER BY id DESC LIMIT 1", (project["id"],)
        ).fetchone()
        project["last_check"] = dict(row) if row else None
        project["task_counts"] = {
            status: sum(task["status"] == status for task in project["tasks"])
            for status in ("todo","doing","blocked","done")
        }
        return project

    def list_projects(self, limit: int = 30) -> list[dict]:
        limit = max(1,min(40,int(limit)))
        rows = self.db.execute(
            "SELECT id FROM projects ORDER BY updated_at DESC,id DESC LIMIT ?",
            (limit,)
        ).fetchall()
        return [self.get_project(row["id"]) for row in rows]

    def add_project_task(self, project_id: object, title: object) -> dict:
        project = self._project_row(project_id)
        title = self._required_text(title, field="작업 이름", maximum=200)
        now = iso_now()
        with self.db:
            cursor = self.db.execute(
                "INSERT INTO project_tasks(project_id,title,status,created_at,updated_at) "
                "VALUES (?,?,?,?,?)", (project["id"],title,"todo",now,now)
            )
            self.db.execute("UPDATE projects SET updated_at=? WHERE id=?", (now,project["id"]))
        return {"id":cursor.lastrowid,"project_id":project["id"],
                "title":title,"status":"todo","updated_at":now}

    def update_project_task(self, project_id: object, task_id: object, status: object) -> dict:
        project = self._project_row(project_id)
        task_id = self._valid_id(task_id)
        if not isinstance(status, str) or status not in ("todo","doing","blocked","done"):
            raise ValueError("작업 상태는 예정/진행/막힘/완료 중 하나여야 합니다.")
        task = self.db.execute(
            "SELECT id,title,status FROM project_tasks WHERE id=? AND project_id=?",
            (task_id,project["id"])
        ).fetchone()
        if task is None:
            raise ValueError("이 프로젝트에 해당 작업이 없습니다.")
        if task["status"] != status:
            now = iso_now()
            with self.db:
                self.db.execute("UPDATE project_tasks SET status=?,updated_at=? WHERE id=?",
                                (status,now,task_id))
                self.db.execute("UPDATE projects SET updated_at=? WHERE id=?",
                                (now,project["id"]))
                self.db.execute(
                    "INSERT INTO project_changes(project_id,task_id,old_status,new_status,actor,changed_at)"
                    " VALUES (?,?,?,?,?,?)",
                    (project["id"],task_id,task["status"],status,"user",now)
                )
        return self.get_project(project["id"])

    def save_project_check(self, project_id: object, check: dict) -> dict:
        project = self._project_row(project_id)
        if not project["repo_full_name"] or str(check.get("repository", "")).casefold() != project["repo_full_name"].casefold():
            raise ValueError("연결된 GitHub 저장소와 확인 대상이 일치하지 않습니다.")
        with self.db:
            self.db.execute(
                "INSERT INTO project_checks(project_id,provider,repository,branch,head_sha,"
                "workflow_state,workflow_conclusion,workflow_url,checked_at)"
                " VALUES (?,?,?,?,?,?,?,?,?)",
                (project["id"],"github",check["repository"],check["branch"],
                 check["head_sha"],check["workflow_state"],check["workflow_conclusion"],
                 check["workflow_url"],iso_now())
            )
        return self.get_project(project["id"])

    def project_changes(self, project_id: object, limit: int = 20) -> list[dict]:
        project = self._project_row(project_id)
        return [dict(row) for row in self.db.execute(
            "SELECT task_id,old_status,new_status,actor,changed_at "
            "FROM project_changes WHERE project_id=? ORDER BY id DESC LIMIT ?",
            (project["id"],max(1,min(50,int(limit))))
        )]


    def start_tool_execution(self, name: str, project_id: int, permission: str) -> int:
        project = self._project_row(project_id)
        if name != "github.public_verify" or permission != "read_external":
            raise ValueError("등록된 읽기 전용 도구만 실행 기록을 남길 수 있습니다.")
        with self.db:
            cur = self.db.execute(
                "INSERT INTO tool_executions(tool_name,project_id,permission,status,requested_at) "
                "VALUES (?,?,?,?,?)",
                (name,project["id"],permission,"started",iso_now())
            )
        return cur.lastrowid

    def finish_tool_execution(self, run_id: int, status: str,
                              outcome: str, sha: str = "") -> dict:
        if type(run_id) is not int or status not in ("completed","failed"):
            raise ValueError("실행 기록 형식이 잘못되었습니다.")
        if outcome not in ("head_observed","head_and_workflow_observed",
                           "provider_unavailable","invalid_evidence"):
            raise ValueError("검증되지 않은 결과 분류입니다.")
        with self.db:
            cur = self.db.execute(
                "UPDATE tool_executions SET status=?,outcome=?,head_sha=?,completed_at=? "
                "WHERE id=? AND status='started'",
                (status,outcome,sha[:40] if status=="completed" else "",iso_now(),run_id)
            )
        if cur.rowcount != 1:
            raise ValueError("이미 종료된 실행이거나 존재하지 않는 기록입니다.")
        return self.get_tool_execution(run_id)

    def get_tool_execution(self, run_id: int) -> dict:
        row = self.db.execute(
            "SELECT id,tool_name,project_id,permission,status,outcome,head_sha,"
            "requested_at,completed_at FROM tool_executions WHERE id=?",(run_id,)
        ).fetchone()
        if row is None:
            raise ValueError("실행 기록이 존재하지 않습니다.")
        return dict(row)

    def recent_tool_executions(self, limit: int = 20) -> list[dict]:
        limit = max(1,min(40,int(limit)))
        return [dict(x) for x in self.db.execute(
            "SELECT id,tool_name,project_id,permission,status,outcome,head_sha,"
            "requested_at,completed_at FROM tool_executions ORDER BY id DESC LIMIT ?",
            (limit,)
        )]

    def close(self):
        self.db.close()
