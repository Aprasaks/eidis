"""Native project workflow must require explicit approval before GitHub reads."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SWIFT = ROOT / "macos/Sources/EidisMac/ApprovedProjectsPanel.swift"
ENTRY = ROOT / "macos/Sources/EidisMac/EidisMacApp.swift"


class ApprovedProjectWorkContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = SWIFT.read_text(encoding="utf-8")
        cls.entry = ENTRY.read_text(encoding="utf-8")

    def test_has_dedicated_native_work_tab(self):
        self.assertIn("ApprovedProjectsPanel(work: projectWork, requestedWorkspace: workspaceRequest)", self.entry)
        self.assertIn('Label("작업", systemImage: "checklist")', self.entry)

    def test_external_check_is_only_in_approved_action(self):
        self.assertIn('func runApprovedCheck(_ proposal: WorkCheckProposal)', self.work)
        self.assertIn('Button("승인하고 공개 GitHub 1회 조회")', self.work)
        self.assertIn("confirmationDialog(", self.work)
        self.assertEqual(self.work.count('fetch("/api/projects/github/check", body: body)'), 1)
        refresh = self.work.split("func refresh() async {", 1)[1].split(
            "func runApprovedCheck", 1)[0]
        self.assertIn('fetch("/api/projects")', refresh)
        self.assertNotIn("github/check", refresh)

    def test_native_manual_task_edits_are_local_only(self):
        self.assertIn('func addTask(projectId: Int, title: String)', self.work)
        self.assertIn('func updateTask(projectId: Int, taskId: Int, next: WorkTaskState)', self.work)
        self.assertIn('fetch("/api/projects/task", body: body)', self.work)
        self.assertIn('fetch("/api/projects/status", body: body)', self.work)
        self.assertIn('Button("예정 작업 추가")', self.work)
        self.assertIn('Menu("상태 변경")', self.work)
        self.assertIn('selected.nextTasks', self.work)
        self.assertIn('selected.blockedTasks', self.work)
        self.assertIn("진행 중 → 예정 순서", self.work)
        writes = self.work.split("func addTask(", 1)[1].split("func runApprovedCheck(", 1)[0]
        self.assertNotIn('fetch("/api/projects/github/check"', writes)
        self.assertIn("자동 재시도하지 않습니다", writes)

    def test_persisted_local_task_state_round_trip(self):
        import json
        import tempfile
        import threading
        from urllib.request import Request, urlopen
        from jarvis.server import make_server

        with tempfile.TemporaryDirectory() as directory:
            server = make_server(port=0, db_path=Path(directory) / "tasks.sqlite3")
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            base = "http://127.0.0.1:" + str(server.server_port)

            def post(path, payload):
                request = Request(
                    base + path,
                    data=json.dumps(payload, ensure_ascii=False).encode(),
                    method="POST",
                    headers={"Content-Type": "application/json", "Origin": base},
                )
                with urlopen(request, timeout=5) as reply:
                    return json.load(reply)

            def get(path):
                with urlopen(base + path, timeout=5) as reply:
                    return json.load(reply)

            try:
                project = post("/api/projects", {"name": "Offline Test", "goal": "계속 이어가기"})["project"]
                task = post("/api/projects/task", {"project_id": project["id"], "title": "다음 작업"})["task"]
                self.assertEqual(task["status"], "todo")
                updated = post("/api/projects/status", {
                    "project_id": project["id"], "task_id": task["id"], "status": "doing"
                })["project"]
                self.assertEqual(updated["task_counts"]["doing"], 1)
                self.assertEqual(updated["tasks"][0]["title"], "다음 작업")
                saved = get("/api/projects")["items"]
                self.assertEqual(saved[0]["tasks"][0]["status"], "doing")
                history = get("/api/projects/history?id=" + str(project["id"]))["items"]
                self.assertEqual(history[0]["old_status"], "todo")
                self.assertEqual(history[0]["new_status"], "doing")
                self.assertEqual(get("/api/tools/history")["items"], [])
            finally:
                server.shutdown()
                server.server_close()
                server.RequestHandlerClass.store.close()
                worker.join(timeout=3)

    def test_approval_scope_and_read_only(self):
        self.assertIn("$0.repoFullName == proposal.repository", self.work)
        self.assertIn("$0.name == proposal.projectName", self.work)
        self.assertIn("response.receipt.projectId == proposal.projectId", self.work)
        self.assertIn("자동 재시도하지 않았습니다", self.work)
        self.assertIn("파일 변경·푸시·배포·삭제는 하지 않습니다", self.work)
        for prohibited in ("shell.exec", "AXUIElementPerformAction",
                           "AXUIElementSetAttributeValue", "git push", "aws deploy"):
            self.assertNotIn(prohibited, self.work)


if __name__ == "__main__":
    unittest.main()
