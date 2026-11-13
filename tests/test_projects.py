"""Project state truthfulness and opt-in public GitHub evidence."""
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
from jarvis.projects import ProjectCheckError, validate_repo, verify_public_github
from jarvis.server import make_server
from jarvis.storage import MemoryStore


class ProjectLedgerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "projects.sqlite3"
        self.store = MemoryStore(self.path)

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_manual_status_and_changes_survive_restart(self):
        project = self.store.create_project("DECHIVE Wiki", "배포까지 마무리", "Aprasaks/eidis")
        self.assertEqual(project["tasks"], [])
        self.assertIsNone(project["last_check"])
        task = self.store.add_project_task(project["id"], "최종 배포 확인")
        self.assertEqual(task["status"], "todo")
        updated = self.store.update_project_task(project["id"], task["id"], "blocked")
        self.assertEqual(updated["task_counts"]["blocked"], 1)
        self.assertEqual(updated["task_counts"]["done"], 0)
        changes = self.store.project_changes(project["id"])
        self.assertEqual(changes[0]["old_status"], "todo")
        self.assertEqual(changes[0]["new_status"], "blocked")
        self.assertEqual(changes[0]["actor"], "user")
        self.store.close()
        reopened = MemoryStore(self.path)
        try:
            loaded = reopened.get_project(project["id"])
            self.assertEqual(loaded["task_counts"]["blocked"], 1)
            self.assertIsNone(loaded["last_check"])
        finally:
            reopened.close()
        self.store = MemoryStore(self.path)

    def test_protect_project_and_task_boundaries(self):
        a = self.store.create_project("A")
        b = self.store.create_project("B")
        task = self.store.add_project_task(a["id"], "개인 작업")
        for bad in (True, 0, -1, "1"):
            with self.subTest(value=bad), self.assertRaises(ValueError):
                self.store.get_project(bad)
        with self.assertRaises(ValueError):
            self.store.update_project_task(b["id"], task["id"], "done")
        with self.assertRaises(ValueError):
            self.store.update_project_task(a["id"], task["id"], "verified")
        with self.assertRaises(ValueError):
            self.store.create_project("a")
        self.assertEqual(self.store.get_project(a["id"])["tasks"][0]["status"], "todo")

    def test_github_check_does_not_change_manual_task_status(self):
        project = self.store.create_project("JARVIS","첫 두뇌","Aprasaks/eidis")
        task = self.store.add_project_task(project["id"], "실기기 마이크 검증")
        verified = {
            "repository":"Aprasaks/eidis", "branch":"main",
            "head_sha":"a"*40, "workflow_state":"completed",
            "workflow_conclusion":"success", "workflow_url":"https://github.com/Aprasaks/eidis/actions/runs/123",
        }
        updated = self.store.save_project_check(project["id"], verified)
        self.assertIsNotNone(updated["last_check"])
        self.assertEqual(updated["last_check"]["head_sha"], "a"*40)
        self.assertEqual(updated["task_counts"]["done"], 0)
        self.assertEqual(updated["tasks"][0]["id"], task["id"])
        self.assertEqual(updated["tasks"][0]["status"], "todo")
        self.assertEqual(self.store.project_changes(project["id"]), [])

    def test_repo_format_rejects_external_urls(self):
        for value in ("https://github.com/owner/repo","owner/repo?x=1",
                      "../etc/passwd","owner/repo/extra", "owner/..", ""):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_repo(value)
        self.assertEqual(validate_repo("Aprasaks/eidis"), "Aprasaks/eidis")
        self.assertEqual(validate_repo("",allow_empty=True), "")

    def test_current_commit_workflow_not_stale_success(self):
        head="b"*40
        seen=[]
        def fake_read(path):
            seen.append(path)
            if path == "/repos/Aprasaks/eidis":
                return {"full_name":"Aprasaks/eidis","private":False,"default_branch":"main"}
            if path.endswith("/branches/main"):
                return {"commit":{"sha":head}}
            return {"workflow_runs":[
                {"head_sha":"a"*40,"status":"completed","conclusion":"success",
                 "html_url":"https://github.com/Aprasaks/eidis/actions/runs/old"}
            ]}
        with patch("jarvis.projects._read_public_api",side_effect=fake_read):
            result=verify_public_github("Aprasaks/eidis")
        self.assertEqual(result["head_sha"],head)
        self.assertEqual(result["workflow_conclusion"],"unknown")
        self.assertEqual(result["workflow_state"],"unavailable")
        self.assertEqual(result["workflow_url"],"")
        self.assertEqual(len(seen),3)
        self.assertTrue(all(x.startswith("/repos/Aprasaks/eidis") for x in seen))

    def test_verified_source_rejects_mismatched_repository(self):
        with patch("jarvis.projects._read_public_api",return_value={
            "full_name":"other/repo","private":False,"default_branch":"main"
        }) as fake:
            with self.assertRaises(ProjectCheckError):
                verify_public_github("Aprasaks/eidis")
        self.assertEqual(fake.call_count,1)

    def test_brain_project_summary_is_local_and_qualified(self):
        project=self.store.create_project("WIKI","공개 배포 전","Aprasaks/eidis")
        task=self.store.add_project_task(project["id"],"AWS 오류")
        self.store.update_project_task(project["id"],task["id"],"blocked")
        brain=JarvisBrain(self.store,JarvisEngine(self.store))
        reply=brain.handle("우리 프로젝트 상태 알려줘")
        self.assertEqual(reply["mode"],"projects")
        self.assertEqual(reply["action"],"project_overview")
        self.assertIn("막힘 1",reply["text"])
        self.assertIn("GitHub 아직",reply["text"])
        self.assertIn("사용자가 입력한",reply["text"])
        self.assertFalse(reply["executed"])

    def test_http_requires_explicit_github_check_and_never_logs_user_task_text(self):
        server=make_server(port=0,db_path=Path(self.temp.name)/"web.sqlite3")
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        base=f"http://127.0.0.1:{server.server_port}"
        def post(path,data,origin=None):
            request=Request(base+path,method="POST",
                data=json.dumps(data,ensure_ascii=False).encode(),
                headers={"Content-Type":"application/json","Origin":origin or base})
            return urlopen(request)
        try:
            with patch("jarvis.server.verify_public_github") as github:
                with post("/api/projects",{
                    "name":"JARVIS", "goal":"검증 시작","repo":"Aprasaks/eidis"
                }) as r:
                    project=json.load(r)["project"]
                pid=project["id"]
                with post("/api/projects/task",{
                    "project_id":pid,"title":"중요한 비밀 문서 삭제 금지"
                }) as r:
                    tid=json.load(r)["task"]["id"]
                with post("/api/projects/status",{
                    "project_id":pid,"task_id":tid,"status":"doing"
                }) as r:
                    self.assertEqual(json.load(r)["project"]["task_counts"]["doing"],1)
                with urlopen(base+"/api/projects") as r:
                    items=json.load(r)["items"]
                self.assertEqual(len(items),1)
                self.assertIsNone(items[0]["last_check"])
                github.assert_not_called()  # no network on create/read/status
                with urlopen(base+f"/api/projects/history?id={pid}") as r:
                    history=json.load(r)["items"]
                self.assertEqual(history[0]["new_status"],"doing")
                with self.assertRaises(HTTPError) as exc:
                    post("/api/projects/github/check",{"project_id":pid},
                         origin="https://attacker.invalid")
                self.assertEqual(exc.exception.code,403)
                github.assert_not_called()
                github.return_value={
                    "repository":"Aprasaks/eidis","branch":"main",
                    "head_sha":"c"*40, "workflow_state":"completed",
                    "workflow_conclusion":"success","workflow_url":""
                }
                with post("/api/projects/github/check",{"project_id":pid}) as r:
                    data=json.load(r)["project"]
                self.assertEqual(data["task_counts"]["done"],0)
                self.assertEqual(data["last_check"]["head_sha"],"c"*40)
                self.assertEqual(github.call_count,1)
                with urlopen(base+"/api/activity") as r:
                    activity=json.load(r)
                self.assertNotIn("중요한 비밀",json.dumps(activity,ensure_ascii=False))
        finally:
            server.shutdown();server.server_close()
            server.RequestHandlerClass.store.close();thread.join(timeout=3)


if __name__=="__main__":
    unittest.main()
