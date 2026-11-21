"""Local, opt-in memory store. Uses only the Python standard library."""
from __future__ import annotations

import sqlite3
import re
import json
import hashlib
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
        # Personal identity facts live apart from ephemeral chat and project tasks.
        # All fields are opt-in and individually editable/deletable. Existing
        # memories and projects are preserved by this additive migration.
        self.db.execute("""
            CREATE TABLE IF NOT EXISTS personal_profile (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                source TEXT NOT NULL,
                confirmed INTEGER NOT NULL DEFAULT 0 CHECK(confirmed IN (0,1)),
                updated_at TEXT NOT NULL
            )
        """)
        self.db.execute("""
            CREATE TABLE IF NOT EXISTS vault_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                category TEXT NOT NULL CHECK(category IN ('ideas','research','projects','references','notes','tasks')),
                project TEXT NOT NULL DEFAULT '',
                tags_json TEXT NOT NULL DEFAULT '[]',
                source_type TEXT NOT NULL CHECK(source_type IN ('user_text','web_page','assistant_response')),
                source_url TEXT NOT NULL DEFAULT '',
                source_status TEXT NOT NULL CHECK(source_status IN ('user_supplied','unverified_external','ai_generated')),
                fingerprint TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1))
            )
        """)
        self.db.execute("CREATE INDEX IF NOT EXISTS vault_category_idx ON vault_items(archived,category,id DESC)")
        self.db.execute("CREATE INDEX IF NOT EXISTS vault_project_idx ON vault_items(archived,project,id DESC)")
        self.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS vault_active_fingerprint_idx ON vault_items(fingerprint) WHERE archived=0")
        # Additive, local-only thought ledger. Hypotheses are never facts.
        self.db.execute("""
            CREATE TABLE IF NOT EXISTS thought_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                topic TEXT NOT NULL,
                hypothesis TEXT NOT NULL,
                source TEXT NOT NULL DEFAULT 'assistant_response'
                    CHECK(source = 'assistant_response'),
                status TEXT NOT NULL DEFAULT 'hypothesis'
                    CHECK(status IN ('hypothesis','user_reviewed','rejected')),
                review_note TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        self.db.execute(
            "CREATE INDEX IF NOT EXISTS thought_records_recent_idx "
            "ON thought_records(updated_at DESC)"
        )
        from .continuity import init_schema
        init_schema(self.db)
        from .study import init_schema as init_study_schema
        init_study_schema(self.db)
        from .action import init_schema as init_action_schema
        init_action_schema(self.db)
        from .research import init_schema as init_research_schema
        init_research_schema(self.db)
        from .verification import init_schema as init_verification_schema
        init_verification_schema(self.db)
        self.db.commit()

    VAULT_CATEGORIES = frozenset({'ideas','research','projects','references','notes','tasks'})
    VAULT_SOURCES = {'user_text':'user_supplied', 'web_page':'unverified_external',
                     'assistant_response':'ai_generated'}
    VAULT_TAGS = (
        ('블로그','블로그'), ('위키','위키'), ('자비스','JARVIS'), ('jarvis','JARVIS'),
        ('dechive','DECHIVE'), ('데카이브','DECHIVE'), ('github','GitHub'), ('깃허브','GitHub'),
        ('노션','Notion'), ('notion','Notion'), ('obsidian','Obsidian'), ('옵시디언','Obsidian'),
        ('영상','영상'), ('유튜브','YouTube'), ('youtube','YouTube'), ('엑셀','Excel'), ('excel','Excel'),
        ('blender','Blender'), ('블렌더','Blender'), ('ai','AI'), ('인공지능','AI'),
    )

    @classmethod
    def classify_vault(cls, text: str) -> str:
        s = text.lower()
        for category, words in (
            ('tasks', ('할 일', '해야 할 일', '투두', 'todo', '마감', '체크리스트')),
            ('ideas', ('아이디어', '기획안', '발상', '구상', '생각난 것')),
            ('projects', ('작업 현황', '진행 상황', '프로젝트 메모', '개발 로그', '작업 기록')),
            ('research', ('연구', '분석', '조사', '공략', '검증', '실험', '보고서')),
            ('references', ('참고', '출처', '링크', '자료', '웹페이지', '사이트', 'https://')),
        ):
            if any(word in s for word in words): return category
        return 'notes'

    @classmethod
    def vault_tags(cls, text: str) -> list[str]:
        s = text.lower()
        return list(dict.fromkeys(label for term,label in cls.VAULT_TAGS if term in s))[:8]

    @classmethod
    def vault_project(cls, text: str) -> str:
        s = text.lower()
        if 'dechive' in s or '데카이브' in s: return 'DECHIVE'
        if 'jarvis' in s or '자비스' in s: return 'JARVIS'
        return ''

    @classmethod
    def _validate_vault(cls, title: object, content: object, category: object,
                        project: object, source_type: object, source_url: object) -> tuple:
        if not isinstance(title,str) or not 1 <= len(title.strip()) <= 160:
            raise ValueError('제목은 1~160자여야 합니다.')
        if not isinstance(content,str) or not 1 <= len(content.strip()) <= 8000:
            raise ValueError('저장할 내용은 1~8000자여야 합니다.')
        if not isinstance(category,str) or category not in cls.VAULT_CATEGORIES:
            raise ValueError('등록된 자료 분류가 아닙니다.')
        if not isinstance(project,str) or len(project) > 80:
            raise ValueError('프로젝트 표기는 80자 이하여야 합니다.')
        if not isinstance(source_type,str) or source_type not in cls.VAULT_SOURCES:
            raise ValueError('자료 출처 종류가 잘못되었습니다.')
        if not isinstance(source_url,str) or len(source_url)>2000:
            raise ValueError('출처 주소가 너무 깁니다.')
        if source_url:
            from urllib.parse import urlsplit
            parsed=urlsplit(source_url)
            if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password:
                raise ValueError('출처 링크는 안전한 HTTPS 주소만 허용합니다.')
        if source_type=='web_page' and not source_url:
            raise ValueError('웹페이지 자료는 실제 출처 주소가 필요합니다.')
        if source_type!='web_page' and source_url:
            raise ValueError('직접 입력한 자료에는 검증되지 않은 웹 출처를 달 수 없습니다.')
        secret_markers=('비밀번호:', 'password:', 'api key:', 'api키:', 'secret key:', 'access token:', '주민등록번호:')
        if any(marker in content.lower() for marker in secret_markers) or re.search(
            r'(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{24,})',content
        ):
            raise ValueError('암호나 인증정보로 보이는 내용은 보관하지 않았습니다.')
        return (title.strip(),content.strip(),category,project.strip(),source_type,source_url)

    def save_vault(self, *, title: object, content: object, category: object = 'notes',
                   project: object = '', source_type: object = 'user_text',
                   source_url: object = '') -> dict:
        title,content,category,project,source_type,source_url = self._validate_vault(
            title,content,category,project,source_type,source_url)
        fingerprint = hashlib.sha256(json.dumps([content,source_type,source_url],ensure_ascii=False).encode()).hexdigest()
        tags = self.vault_tags(title+' '+content+' '+project)
        now=iso_now()
        try:
            with self.db:
                cursor=self.db.execute("""
                    INSERT INTO vault_items(title,content,category,project,tags_json,source_type,
                    source_url,source_status,fingerprint,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """,(title,content,category,project,json.dumps(tags,ensure_ascii=False),source_type,
                      source_url,self.VAULT_SOURCES[source_type],fingerprint,now,now))
            result=self.get_vault(cursor.lastrowid)
            result['duplicate']=False
            return result
        except sqlite3.IntegrityError:
            row=self.db.execute('SELECT id FROM vault_items WHERE fingerprint=? AND archived=0',(fingerprint,)).fetchone()
            if row is None: raise
            result=self.get_vault(row['id'])
            result['duplicate']=True
            return result

    @staticmethod
    def _vault_row(row: sqlite3.Row) -> dict:
        d=dict(row)
        d.pop('fingerprint', None)  # Internal dedup token is not an exported fact.
        d['tags']=json.loads(d.pop('tags_json'))
        d['archived']=bool(d['archived'])
        return d

    def get_vault(self, item_id: object) -> dict:
        item_id=self._valid_id(item_id)
        row=self.db.execute('SELECT * FROM vault_items WHERE id=?',(item_id,)).fetchone()
        if row is None: raise ValueError('저장한 자료가 없습니다.')
        return self._vault_row(row)

    def search_vault(self, query: str = '', category: str = '', limit: int = 30) -> dict:
        if not isinstance(query,str) or len(query)>120 or not isinstance(category,str):
            raise ValueError('검색어는 120자 이하여야 합니다.')
        if category and category not in self.VAULT_CATEGORIES:
            raise ValueError('지원하지 않는 자료 분류입니다.')
        if type(limit) is not int: raise ValueError('검색 개수가 올바르지 않습니다.')
        limit=max(1,min(50,limit))
        conditions=['archived=0']
        values=[]
        if category:
            conditions.append('category=?'); values.append(category)
        for word in query.strip().split()[:6]:
            escaped=word.replace('!','!!').replace('%','!%').replace('_','!_')
            conditions.append("(title LIKE ? ESCAPE '!' OR content LIKE ? ESCAPE '!' OR tags_json LIKE ? ESCAPE '!' OR project LIKE ? ESCAPE '!')")
            values.extend([f'%{escaped}%']*4)
        where=' AND '.join(conditions)
        total=self.db.execute('SELECT COUNT(*) FROM vault_items WHERE '+where,values).fetchone()[0]
        rows=self.db.execute('SELECT * FROM vault_items WHERE '+where+' ORDER BY id DESC LIMIT ?',values+[limit]).fetchall()
        counts={row['category']:row['n'] for row in self.db.execute(
            'SELECT category,COUNT(*) AS n FROM vault_items WHERE archived=0 GROUP BY category')}
        return {'items':[self._vault_row(r) for r in rows],'total':total,'counts':counts}

    def archive_vault(self, item_id: object) -> bool:
        item_id=self._valid_id(item_id)
        with self.db:
            row=self.db.execute('UPDATE vault_items SET archived=1,updated_at=? WHERE id=? AND archived=0',
                                (iso_now(),item_id))
        return row.rowcount==1

    def restore_vault(self, item_id: object) -> bool:
        item_id=self._valid_id(item_id)
        with self.db:
            try:
                row=self.db.execute('UPDATE vault_items SET archived=0,updated_at=? WHERE id=? AND archived=1',
                                    (iso_now(),item_id))
            except sqlite3.IntegrityError as exc:
                raise ValueError('동일한 내용이 이미 보관함에 있습니다.') from exc
        return row.rowcount==1

    PROFILE_FIELDS = frozenset({
        "display_name", "identity", "values", "working_style",
        "communication_style", "environment", "assistant_role", "goals",
    })

    def list_profile(self) -> list[dict]:
        return [dict(row) for row in self.db.execute(
            "SELECT key,value,source,confirmed,updated_at FROM personal_profile ORDER BY key"
        )]

    def upsert_profile(self, key: object, value: object,
                       source: str = "user_direct", *, confirmed: bool = True) -> dict:
        if not isinstance(key, str) or key not in self.PROFILE_FIELDS:
            raise ValueError("지원하지 않는 프로필 항목입니다.")
        if not isinstance(value, str) or not 1 <= len(value.strip()) <= 350:
            raise ValueError("프로필 내용은 1~350자 이내여야 합니다.")
        # The Mac client and local API must both reject common secrets.
        secret_markers = ("비밀번호", "주민번호", "신용카드", "패스워드", "api키", "api key",
                          "인증토큰", "secret key", "access token", "private key")
        if any(marker in value.lower() for marker in secret_markers) or re.search(
            r"(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{24,})", value
        ):
            raise ValueError("비밀번호나 API 인증정보는 사용자 프로필에 저장하지 않습니다.")
        if source not in ("user_direct", "user_approved_seed"):
            raise ValueError("확인되지 않은 정보 출처입니다.")
        if not confirmed:
            raise ValueError("사용자가 확인하지 않은 프로필은 저장하지 않습니다.")
        value = value.strip()
        now = iso_now()
        with self.db:
            self.db.execute("""
                INSERT INTO personal_profile(key,value,source,confirmed,updated_at)
                VALUES (?,?,?,?,?)
                ON CONFLICT(key) DO UPDATE SET value=excluded.value,
                    source=excluded.source,confirmed=excluded.confirmed,
                    updated_at=excluded.updated_at
            """, (key, value, source, 1, now))
        return dict(self.db.execute(
            "SELECT key,value,source,confirmed,updated_at FROM personal_profile WHERE key=?",
            (key,)
        ).fetchone())

    def delete_profile(self, key: object) -> bool:
        if not isinstance(key, str) or key not in self.PROFILE_FIELDS:
            raise ValueError("지원하지 않는 프로필 항목입니다.")
        with self.db:
            removed = self.db.execute("DELETE FROM personal_profile WHERE key=?", (key,))
        return removed.rowcount == 1

    @staticmethod
    def _thought_text(value: object, label: str, maximum: int) -> str:
        if not isinstance(value, str) or not 1 <= len(value.strip()) <= maximum:
            raise ValueError(f"{label}은(는) 1~{maximum}자로 작성해 주세요.")
        text = value.strip()
        forbidden = ("비밀번호:", "password:", "api key:", "api키:", "access token:",
                     "secret key:", "주민등록번호:", "private key:")
        if any(term in text.lower() for term in forbidden) or re.search(
            r"(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{24,})", text
        ):
            raise ValueError("비밀번호나 API 인증정보는 사고 기록에 저장하지 않습니다.")
        return text

    def create_thought(self, topic: object, hypothesis: object) -> dict:
        """Explicit user-approved save only; never invoked by model inference."""
        topic = self._thought_text(topic, "주제", 300)
        hypothesis = self._thought_text(hypothesis, "판단", 1500)
        now = iso_now()
        with self.db:
            row = self.db.execute(
                "INSERT INTO thought_records(topic,hypothesis,source,status,created_at,updated_at) "
                "VALUES (?,?,'assistant_response','hypothesis',?,?)",
                (topic, hypothesis, now, now)
            )
        return self.get_thought(row.lastrowid)

    def get_thought(self, thought_id: object) -> dict:
        thought_id = self._valid_id(thought_id)
        row = self.db.execute(
            "SELECT id,topic,hypothesis,source,status,review_note,created_at,updated_at "
            "FROM thought_records WHERE id=?", (thought_id,)
        ).fetchone()
        if row is None:
            raise ValueError("사고 기록을 찾을 수 없습니다.")
        return dict(row)

    def list_thoughts(self, limit: int = 12) -> list[dict]:
        if type(limit) is not int:
            raise ValueError("조회 개수가 올바르지 않습니다.")
        return [dict(row) for row in self.db.execute(
            "SELECT id,topic,hypothesis,source,status,review_note,created_at,updated_at "
            "FROM thought_records ORDER BY id DESC LIMIT ?",
            (min(max(limit, 1), 25),)
        )]

    def review_thought(self, thought_id: object, status: object, note: object) -> dict:
        """Only an explicit user API action may mark/reject a thought."""
        thought_id = self._valid_id(thought_id)
        if status not in ("user_reviewed", "rejected", "hypothesis"):
            raise ValueError("검토 상태는 hypothesis/user_reviewed/rejected 중 하나여야 합니다.")
        note = self._thought_text(note, "검토 이유", 600)
        with self.db:
            updated = self.db.execute(
                "UPDATE thought_records SET status=?,review_note=?,updated_at=? WHERE id=?",
                (status, note, iso_now(), thought_id)
            )
        if updated.rowcount != 1:
            raise ValueError("사고 기록을 찾을 수 없습니다.")
        return self.get_thought(thought_id)

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
