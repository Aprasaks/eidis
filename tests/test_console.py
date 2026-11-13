"""Unified console source contract.

No raw transcripts or screenshot data belong in the durable activity stream.
"""
import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.request import Request, urlopen

from jarvis.server import make_server
from jarvis.storage import MemoryStore


class ConsoleActivityTests(unittest.TestCase):
    def test_activity_ids_are_monotonic_and_do_not_include_memory_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = MemoryStore(Path(tmp) / "test.sqlite3")
            try:
                store.add_memory("테스트용 비공개 메모")
                store.record_event("remember", "handled")
                store.record_event("open_dashboard", "handled")
                entries = store.recent_activity(50)
                self.assertEqual([x["id"] for x in entries], [2, 1])
                self.assertEqual([x["category"] for x in entries], ["open_dashboard", "remember"])
                self.assertNotIn("비공개 메모", json.dumps(entries, ensure_ascii=False))
            finally:
                store.close()

    def test_server_exposes_local_console_js_and_activity_meta(self):
        with tempfile.TemporaryDirectory() as tmp:
            server = make_server(port=0, db_path=Path(tmp) / "server.sqlite3")
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base = f"http://127.0.0.1:{server.server_port}"
            try:
                with urlopen(base + "/terminal.js") as response:
                    script = response.read().decode("utf-8")
                self.assertIn("JarvisTerminal", script)
                self.assertNotIn("eval(", script)
                body = json.dumps({"text": "자비스 대시보드 띄워"}, ensure_ascii=False).encode()
                request = Request(
                    base + "/api/command", method="POST", data=body,
                    headers={"Content-Type": "application/json", "Origin": base}
                )
                with urlopen(request) as response:
                    self.assertEqual(json.load(response)["action"], "open_dashboard")
                with urlopen(base + "/api/activity") as response:
                    entries = json.load(response)["items"]
                self.assertEqual(entries[0]["category"], "open_dashboard")
                self.assertIsInstance(entries[0]["id"], int)
                self.assertNotIn("대시보드 띄워", json.dumps(entries, ensure_ascii=False))
            finally:
                server.shutdown()
                server.server_close()
                server.RequestHandlerClass.store.close()
                thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
