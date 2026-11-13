"""Readiness diagnostics must be local, truthful, and side-effect free."""
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from jarvis.server import make_server

ROOT = Path(__file__).resolve().parents[1]


class ReadinessDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.server = make_server(port=0,db_path=Path(self.tmp.name)/"readiness.sqlite3")
        self.thread = threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.server.RequestHandlerClass.store.close()
        self.thread.join(timeout=3)
        self.tmp.cleanup()

    def test_read_only_report_has_evidence_boundaries_and_no_secrets(self):
        with patch("jarvis.tools.verify_public_github") as github, \
             patch("jarvis.brain.urlopen") as paid_ai, \
             patch("jarvis.projects._read_public_api") as public_api:
            with urlopen(self.base+"/api/diagnostics",timeout=5) as response:
                self.assertEqual(response.status,200)
                result=json.load(response)
            github.assert_not_called()
            paid_ai.assert_not_called()
            public_api.assert_not_called()

        self.assertEqual(result["scope"],"local_read_only")
        self.assertEqual(result["server"]["status"],"reachable")
        self.assertEqual(result["server"]["host"],"127.0.0.1")
        self.assertEqual(result["database"]["status"],"ok")
        self.assertTrue(result["database"]["read_checked"])
        self.assertFalse(result["database"]["write_checked"])
        self.assertEqual(result["projects"]["exact_count"],0)
        self.assertEqual(result["tools"]["latest_run"],[])
        self.assertFalse(result["tools"]["manifest"]["write_tools_enabled"])
        self.assertIn("mac_speech_transcription",result["not_verified"])
        self.assertIn("github_live_network",result["not_verified"])
        report=json.dumps(result,ensure_ascii=False)
        self.assertNotIn("OPENAI_API_KEY",report)
        self.assertNotIn("token",report.lower())

    def test_report_does_not_mutate_sqlite_or_record_activity(self):
        self.assertEqual(self.server.RequestHandlerClass.store.recent_activity(),[])
        before=self.server.RequestHandlerClass.store.db.total_changes
        for _ in range(2):
            with urlopen(self.base+"/api/diagnostics") as response:
                self.assertEqual(json.load(response)["database"]["status"],"ok")
        after=self.server.RequestHandlerClass.store.db.total_changes
        self.assertEqual(before,after)
        self.assertEqual(self.server.RequestHandlerClass.store.recent_activity(),[])

    def test_project_names_and_task_titles_are_not_in_diagnostics(self):
        store=self.server.RequestHandlerClass.store
        project=store.create_project("내부 경영 계획", "숨겨야 하는 목표", "")
        store.add_project_task(project["id"],"외부에 보내지 않을 작업 이름")
        with urlopen(self.base+"/api/diagnostics") as response:
            report=response.read().decode("utf-8")
        self.assertIn('"exact_count": 1',report)
        self.assertNotIn("내부 경영 계획",report)
        self.assertNotIn("숨겨야 하는 목표",report)
        self.assertNotIn("외부에 보내지 않을",report)

    def test_remote_origin_and_host_are_rejected(self):
        request=Request(self.base+"/api/diagnostics",headers={"Origin":"https://evil.test"})
        with self.assertRaises(HTTPError) as error:
            urlopen(request)
        self.assertEqual(error.exception.code,403)

    def test_native_diagnostics_are_opt_in_and_do_not_request_permissions(self):
        src=(ROOT/"macos/Sources/EidisMac/MacReadinessPanel.swift").read_text()
        app=(ROOT/"macos/Sources/EidisMac/EidisMacApp.swift").read_text()
        launcher=(ROOT/"START_JARVIS_MAC.command").read_text()
        self.assertIn("MacReadinessPanel()",app)
        self.assertIn('Label("진단", systemImage:',app)
        self.assertIn("func run() async",src)
        self.assertIn('Button("진단 실행")',src)
        self.assertIn("CGPreflightScreenCaptureAccess()",src)
        self.assertIn("AVCaptureDevice.authorizationStatus(for: .audio)",src)
        self.assertIn("SFSpeechRecognizer.authorizationStatus()",src)
        self.assertNotIn("AVCaptureDevice.requestAccess",src)
        self.assertNotIn("SFSpeechRecognizer.requestAuthorization",src)
        self.assertNotIn("CGRequestScreenCaptureAccess()",src)
        self.assertNotIn("verify_public_github",src)
        self.assertIn("/api/diagnostics",launcher)
        self.assertIn("if [ \"$ready\" -ne 1 ]",launcher)


if __name__=="__main__":
    unittest.main()
