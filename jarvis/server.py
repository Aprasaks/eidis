"""Loopback-only standard-library HTTP server. No external service/API key."""
from __future__ import annotations

import json
import mimetypes
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlsplit

from .engine import JarvisEngine, CAPABILITIES
from .design import DesignError, RemoteDesignError, remote_ready, suggest_designs
from .storage import MemoryStore

WEB_DIR = Path(__file__).resolve().parent.parent / "web"
DB_PATH = Path(os.environ.get("JARVIS_DB", str(Path.home() / ".jarvis-lab" / "memory.sqlite3")))
MAX_BODY = 12_000


class JarvisHandler(BaseHTTPRequestHandler):
    store: MemoryStore
    engine: JarvisEngine
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
                                    "note": "프로토타입. LLM, 실제 화면 이해, Mac 제어는 미연결."})
        if path == "/api/memories":
            return self._json(200, {"items": self.store.recent_memories()})
        if path == "/api/activity":
            return self._json(200, {"items": self.store.recent_activity()})
        if path == "/":
            path = "/index.html"
        if path not in ("/index.html", "/style.css", "/app.js"):
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
        if path not in ("/api/command", "/api/design/suggest"):
            return self._json(404, {"error": "알 수 없는 경로"})
        if not self._same_origin():
            return self._json(403, {"error": "로컬 앱에서만 요청할 수 있습니다."})
        if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
            return self._json(415, {"error": "JSON만 지원합니다."})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 1 <= size <= MAX_BODY:
                return self._json(413, {"error": "요청이 너무 큽니다."})
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict):
                raise ValueError("JSON 객체로 요청해야 합니다.")
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
    handler = type("LocalHandler", (JarvisHandler,), {"store": store, "engine": JarvisEngine(store)})
    return HTTPServer(("127.0.0.1", port), handler)
