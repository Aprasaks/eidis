"""Loopback-only standard-library HTTP server. No external service/API key."""
from __future__ import annotations

import json
import mimetypes
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

from .engine import JarvisEngine, CAPABILITIES
from .brain import JarvisBrain, BrainError, BrainProviderError, brain_ready, MAX_REMOTE_CALLS
from .design import DesignError, RemoteDesignError, remote_ready, suggest_designs
from .vision import VisionError, VisionRemoteError, vision_ready, analyze_screen, validate_image
from .storage import MemoryStore
from .projects import ProjectCheckError, verify_public_github

WEB_DIR = Path(__file__).resolve().parent.parent / "web"
DB_PATH = Path(os.environ.get("JARVIS_DB", str(Path.home() / ".jarvis-lab" / "memory.sqlite3")))
MAX_BODY = 12_000
MAX_VISION_BODY = 1_450_000
MAX_VISION_CALLS = 3


class JarvisHandler(BaseHTTPRequestHandler):
    store: MemoryStore
    engine: JarvisEngine
    brain: JarvisBrain
    server_version = "JARVIS-Lab/0.1"

    def _json(self, status: int, payload: dict) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _same_origin(self) -> bool:
        origin = self.headers.get("Origin", "")
        host = self.headers.get("Host", "")
        # Browser fetch() sends origin. Reject foreign origins, and non-loopback Host.
        allowed = (f"127.0.0.1:{self.server.server_port}", f"localhost:{self.server.server_port}")
        return host in allowed and (not origin or origin in tuple("http://" + h for h in allowed))

    def do_GET(self):  # noqa N802
        if not self._same_origin():
            return self._json(403, {"error": "로컬 앱에서만 접근할 수 있습니다."})
        path = urlsplit(self.path).path
        if path == "/api/status":
            return self._json(200, {"name": "JARVIS Lab", "version": "0.1.0",
                                    "capabilities": CAPABILITIES, "memory_count": self.store.count_memories(),
                                    "design": {"local_available": True, "remote_configured": remote_ready()},
                                    "brain": {"local_context": True, "remote_configured": brain_ready(),
                                              "remaining": max(0, MAX_REMOTE_CALLS - self.brain.remote_calls),
                                              "history": "RAM only; explicit notes use SQLite"},
                                    "vision": {"remote_configured": vision_ready(),
                                               "remaining": max(0, MAX_VISION_CALLS - self.server.vision_calls)},
                                    "note": "프로토타입. LLM, 실제 화면 이해, Mac 제어는 미연결."})
        if path == "/api/memories":
            return self._json(200, {"items": self.store.recent_memories()})
        if path == "/api/projects":
            return self._json(200, {"items": self.store.list_projects()})
        if path == "/api/projects/history":
            try:
                values = parse_qs(urlsplit(self.path).query)
                pid = int(values.get("id", [""])[0])
                return self._json(200, {"items": self.store.project_changes(pid)})
            except (ValueError, IndexError) as exc:
                return self._json(400, {"error": str(exc)})
        if path == "/api/activity":
            return self._json(200, {"items": self.store.recent_activity(50)})
        if path == "/":
            path = "/index.html"
        if path not in ("/index.html", "/style.css", "/terminal.js", "/app.js"):
            self.send_error(404)
            return
        filepath = WEB_DIR / path.lstrip("/")
        data = filepath.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", (mimetypes.guess_type(str(filepath))[0] or "text/plain") + "; charset=utf-8")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'self'; img-src 'self' blob: data:; script-src 'self'; style-src 'self'; connect-src 'self'; media-src 'self' blob:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):  # noqa N802
        path = urlsplit(self.path).path
        if path not in ("/api/command", "/api/chat", "/api/design/suggest", "/api/vision/analyze",
                         "/api/projects", "/api/projects/task", "/api/projects/status",
                         "/api/projects/github/check"):
            return self._json(404, {"error": "알 수 없는 경로"})
        if not self._same_origin():
            return self._json(403, {"error": "로컬 앱에서만 요청할 수 있습니다."})
        if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
            return self._json(415, {"error": "JSON만 지원합니다."})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 1 <= size <= (MAX_VISION_BODY if path == '/api/vision/analyze' else MAX_BODY):
                return self._json(413, {"error": "요청이 너무 큽니다."})
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict):
                raise ValueError("JSON 객체로 요청해야 합니다.")
            if path == "/api/projects":
                project = self.store.create_project(
                    data.get("name"), data.get("goal", ""), data.get("repo", "")
                )
                self.store.record_event("project_created", "user")
                return self._json(200, {"project": project})
            if path == "/api/projects/task":
                task = self.store.add_project_task(data.get("project_id"), data.get("title"))
                self.store.record_event("project_task_added", "user")
                return self._json(200, {"task": task})
            if path == "/api/projects/status":
                project = self.store.update_project_task(
                    data.get("project_id"), data.get("task_id"), data.get("status")
                )
                self.store.record_event("project_task_status", "user")
                return self._json(200, {"project": project})
            if path == "/api/projects/github/check":
                project = self.store._project_row(data.get("project_id"))
                if not project["repo_full_name"]:
                    raise ValueError("프로젝트에 GitHub owner/repo가 설정되어 있지 않습니다.")
                # No auto-refresh, no credentials, no network on page load.
                check = verify_public_github(project["repo_full_name"])
                checked = self.store.save_project_check(project["id"], check)
                self.store.record_event("project_github_checked", "verified")
                return self._json(200, {"project": checked})
            if path == "/api/chat":
                reply = self.brain.handle(
                    data.get("text", ""), conversation_id=data.get("conversation_id"),
                    remote_consent=data.get("remote_consent") is True,
                )
                return self._json(200, reply)
            if path == "/api/vision/analyze":
                if data.get("consent") is not True:
                    raise VisionError("이번 화면 한 장의 외부 전송에 동의해 주세요.")
                if not vision_ready():
                    raise VisionError("외부 AI 화면 분석이 비활성화되어 있습니다.")
                if self.server.vision_calls >= MAX_VISION_CALLS:
                    raise VisionError("현재 서버의 화면 분석 허용 횟수를 모두 사용했습니다. 추가 과금 방지를 위해 중지했습니다.")
                question = data.get("question", "")
                if not isinstance(question, str) or not 3 <= len(question.strip()) <= 450:
                    raise VisionError("화면 질문은 3~450자로 입력해 주세요.")
                image = validate_image(data.get("image", ""))
                # Only validated requests count toward the cap. Count before calling
                # the provider because even a provider error may incur usage.
                self.server.vision_calls += 1
                return self._json(200, analyze_screen(question, image, consent=True))
            if path == "/api/design/suggest":
                prompt = data.get("prompt", "")
                provider = data.get("provider", "rules")
                if provider == "ai" and data.get("consent") is not True:
                    raise DesignError("이번 요청의 외부 AI 전송 동의를 확인해 주세요.")
                result = suggest_designs(prompt, provider=provider, consent=data.get("consent") is True)
                # Do not retain the text of the design request or the raw AI response.
                self.store.record_event("design_suggestions", provider if provider in ("ai", "rules") else "invalid")
                return self._json(200, result)
            result = self.engine.handle(data.get("text", ""))
            return self._json(200, result)
        except ProjectCheckError as exc:
            return self._json(502, {"error": str(exc)})
        except BrainProviderError as exc:
            return self._json(502, {"error": str(exc)})
        except VisionRemoteError as exc:
            return self._json(502, {"error": str(exc)})
        except RemoteDesignError as exc:
            return self._json(502, {"error": str(exc)})
        except (ValueError, json.JSONDecodeError, AttributeError) as exc:
            return self._json(400, {"error": str(exc)})

    def log_message(self, fmt, *args):
        # Avoid logging user utterances to stdout.
        if self.path.startswith("/api"):
            return
        super().log_message(fmt, *args)


def make_server(host: str = "127.0.0.1", port: int = 8765, db_path: Path | None = None):
    if host not in ("127.0.0.1", "localhost"):
        raise ValueError("원격 노출을 막기 위해 localhost만 허용합니다.")
    store = MemoryStore(db_path or DB_PATH)
    engine = JarvisEngine(store)
    brain = JarvisBrain(store, engine)
    handler = type("LocalHandler", (JarvisHandler,),
                   {"store": store, "engine": engine, "brain": brain})
    server = HTTPServer(("127.0.0.1", port), handler)
    server.vision_calls = 0
    return server
