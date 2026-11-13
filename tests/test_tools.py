"""End-to-end limits and verification for JARVIS's first actionable tool."""
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from jarvis.brain import JarvisBrain
from jarvis.engine import JarvisEngine
from jarvis.server import make_server
from jarvis.storage import MemoryStore
from jarvis.tools import ToolDenied, ToolExecutionError, ToolRunner, MAX_CHECKS_PER_PROCESS


def fixture(repo="Aprasaks/eidis", *, workflow=True):
    return {
        "repository": repo, "branch": "main", "head_sha": "f"*40,
        "workflow_state": "completed" if workflow else "unavailable",
        "workflow_conclusion": "success" if workflow else "unknown",
        "workflow_url": "https://github.com/Aprasaks/eidis/actions/runs/1234" if workflow else "",
    }


class ToolRunnerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = MemoryStore(Path(self.tmp.name)/"tools.sqlite3")
        self.project = self.store.create_project("JARVIS","실기기 연결","Aprasaks/eidis")
        self.tool = ToolRunner(self.store)

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_registry_is_allowlisted_read_only(self):
        manifest = self.tool.manifest()
        self.assertEqual([x["name"] for x in manifest["tools"]], ["github.public_verify"])
        self.assertEqual(manifest["tools"][0]["permission"], "read_external")
        self.assertFalse(manifest["write_tools_enabled"])
        with self.assertRaises(ToolDenied):
            self.tool.execute("shell.exec",self.project["id"],explicit_request=True)
        with self.assertRaises(ToolDenied):
            self.tool.execute("github.public_verify",self.project["id"])
        self.assertEqual(self.store.recent_tool_executions(),[])

    def test_verified_run_is_audited_without_completing_tasks(self):
        task=self.store.add_project_task(self.project["id"],"Mac 앱 실기기 검증")
        with patch("jarvis.tools.verify_public_github",return_value=fixture()) as fetch:
            outcome=self.tool.execute("github.public_verify",self.project["id"],explicit_request=True)
        fetch.assert_called_once_with("Aprasaks/eidis")
        receipt=outcome["receipt"]
        self.assertEqual(receipt["permission"],"read_external")
        self.assertEqual(receipt["status"],"completed")
        self.assertEqual(receipt["outcome"],"head_and_workflow_observed")
        self.assertEqual(receipt["head_sha"],"f"*40)
        self.assertEqual(outcome["project"]["last_check"]["workflow_conclusion"],"success")
        self.assertEqual(outcome["project"]["tasks"][0]["id"],task["id"])
        self.assertEqual(outcome["project"]["tasks"][0]["status"],"todo")
        self.assertEqual(self.store.project_changes(self.project["id"]),[])
        self.assertEqual(self.store.recent_tool_executions()[0]["id"],receipt["id"])

    def test_missing_same_head_workflow_is_not_a_green_check(self):
        with patch("jarvis.tools.verify_public_github",return_value=fixture(workflow=False)):
            result=self.tool.execute("github.public_verify",self.project["id"],explicit_request=True)
        self.assertEqual(result["receipt"]["outcome"],"head_observed")
        self.assertEqual(result["project"]["last_check"]["workflow_conclusion"],"unknown")

    def test_provider_failure_is_audited_and_never_claimed_success(self):
        with patch("jarvis.tools.verify_public_github",side_effect=RuntimeError("token and private error")):
            with self.assertRaises(ToolExecutionError) as err:
                self.tool.execute("github.public_verify",self.project["id"],explicit_request=True)
        self.assertNotIn("token",str(err.exception))
        self.assertIsNone(self.store.get_project(self.project["id"])["last_check"])
        receipt=self.store.recent_tool_executions()[0]
        self.assertEqual(receipt["status"],"failed")
        self.assertEqual(receipt["outcome"],"provider_unavailable")
        self.assertNotIn("token",json.dumps(self.store.recent_activity()))

    def test_malformed_data_and_wrong_workflow_link_is_rejected(self):
        bad=fixture()
        bad["workflow_url"]="https://github.com/other/project/actions/runs/5"
        with patch("jarvis.tools.verify_public_github",return_value=bad):
            with self.assertRaises(ToolExecutionError):
                self.tool.execute("github.public_verify",self.project["id"],explicit_request=True)
        self.assertEqual(self.store.recent_tool_executions()[0]["outcome"],"invalid_evidence")

    def test_attempt_limit_applies_before_next_provider_call(self):
        with patch("jarvis.tools.verify_public_github",return_value=fixture()) as fetch:
            for _ in range(MAX_CHECKS_PER_PROCESS):
                self.tool.execute("github.public_verify",self.project["id"],explicit_request=True)
            with self.assertRaises(ToolDenied):
                self.tool.execute("github.public_verify",self.project["id"],explicit_request=True)
        self.assertEqual(fetch.call_count,MAX_CHECKS_PER_PROCESS)
        self.assertEqual(len(self.store.recent_tool_executions()),MAX_CHECKS_PER_PROCESS)

    def test_chat_explicit_language_triggers_actual_tool_only_once(self):
        brain=JarvisBrain(self.store,JarvisEngine(self.store),self.tool)
        with patch("jarvis.tools.verify_public_github",return_value=fixture()) as fetch:
            r=brain.handle("자비스, 내 GitHub 프로젝트 상태 확인해")
        self.assertEqual(r["action"],"tool_github_checked")
        self.assertTrue(r["executed"])
        self.assertEqual(r["brain_source"],"verified_public_api")
        self.assertIn("HEAD",r["text"])
        self.assertIn("보증하지",r["text"])
        self.assertEqual(r["tool_receipt"]["status"],"completed")
        self.assertEqual(fetch.call_count,1)
        self.assertNotIn("내 GitHub 프로젝트",json.dumps(self.store.recent_activity(),ensure_ascii=False))

    def test_ambiguous_and_negative_queries_never_send_network(self):
        self.store.create_project("Dechive Wiki","배포","Aprasaks/dechive-wiki")
        brain=JarvisBrain(self.store,JarvisEngine(self.store),self.tool)
        with patch("jarvis.tools.verify_public_github") as fetch:
            ambiguous=brain.handle("자비스, 내 GitHub 프로젝트 상태 확인해")
            negative=brain.handle("GitHub 확인하지 마")
        self.assertEqual(ambiguous["action"],"tool_target_ambiguous")
        self.assertIn("지정해",ambiguous["text"])
        self.assertNotEqual(negative["action"],"tool_github_checked")
        fetch.assert_not_called()
        self.assertEqual(self.store.recent_tool_executions(),[])

    def test_named_project_in_multi_project_set(self):
        self.store.create_project("Dechive Wiki","배포","Aprasaks/dechive-wiki")
        brain=JarvisBrain(self.store,JarvisEngine(self.store),self.tool)
        with patch("jarvis.tools.verify_public_github",return_value=fixture()) as fetch:
            result=brain.handle("자비스 eidis GitHub 상태 확인해")
        self.assertEqual(result["action"],"tool_github_checked")
        self.assertEqual(fetch.call_count,1)
        self.assertEqual(self.store.list_projects()[0]["last_check"],None)

    def test_http_api_and_activity_are_separate_from_execution_receipts(self):
        server=make_server(port=0,db_path=Path(self.tmp.name)/"web.sqlite3")
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        base=f"http://127.0.0.1:{server.server_port}"
        def post(path,payload,origin=None):
            data=json.dumps(payload,ensure_ascii=False).encode()
            req=Request(base+path,data=data,method="POST",
                        headers={"Content-Type":"application/json","Origin":origin or base})
            return urlopen(req)
        try:
            with urlopen(base+"/api/tools") as resp:
                self.assertFalse(json.load(resp)["write_tools_enabled"])
            with urlopen(base+"/api/tools/history") as resp:
                self.assertEqual(json.load(resp)["items"],[])
            with post("/api/projects",{"name":"JARVIS","repo":"Aprasaks/eidis"}) as resp:
                project=json.load(resp)["project"]
            with patch("jarvis.tools.verify_public_github",return_value=fixture()) as inspector:
                with post("/api/chat",{
                    "text":"자비스 내 GitHub 프로젝트 상태 확인해",
                    "remote_consent":False
                }) as resp:
                    answer=json.load(resp)
            self.assertEqual(answer["action"],"tool_github_checked")
            inspector.assert_called_once()
            with urlopen(base+"/api/tools/history") as resp:
                receipts=json.load(resp)["items"]
            self.assertEqual(receipts[0]["project_id"],project["id"])
            self.assertEqual(receipts[0]["status"],"completed")
            with urlopen(base+"/api/projects") as resp:
                projects=json.load(resp)["items"]
            self.assertEqual(projects[0]["last_check"]["head_sha"],"f"*40)
            with urlopen(base+"/api/activity") as resp:
                activity=json.load(resp)
            self.assertNotIn("내 GitHub 프로젝트",json.dumps(activity,ensure_ascii=False))
            with self.assertRaises(HTTPError) as denied:
                post("/api/chat",{"text":"GitHub 상태 확인해"},
                     origin="https://evil.example")
            self.assertEqual(denied.exception.code,403)
        finally:
            server.shutdown()
            server.server_close()
            server.RequestHandlerClass.store.close()
            thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
