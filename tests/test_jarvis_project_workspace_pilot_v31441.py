from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/"macos/Sources/EidisMac"
UI=(SRC/"JarvisCommandCenterView.swift").read_text()
WORK=(SRC/"JarvisProjectWorkspace.swift").read_text()
AGENT=(SRC/"JarvisAgentTerminalBay.swift").read_text()
MODEL=(SRC/"JarvisLiveDashboard.swift").read_text()
CORE=(SRC/"JarvisFullscreenOverlay.swift").read_text()

class ProjectWorkspacePilot(unittest.TestCase):
    def test_four_project_routes_no_unregistered_jobs(self):
        for domain in ("dechive.dev","dechive.app","군산.com","gunsan-table-tennis-association.vercel.app"):  # 2026-11-27: 실제 도메인 군산.com
            self.assertIn(domain,WORK)
        self.assertIn("ForEach(JarvisWorkroomProject.allCases)",UI)
        self.assertIn("if project == .dev",WORK)
        self.assertIn("운영 업무 미등록",WORK)
        self.assertIn("model.workroomProject = project",UI)
        self.assertIn("model.workroomProject = nil",UI)
        self.assertIn("liveDashboard.workroomProject == nil",CORE)

    def test_real_colored_terminals_and_deduplicated_health(self):
        self.assertIn("id.workroomAccent",UI)
        self.assertIn("let laneHeights = Array(repeating: laneHeight",UI)
        self.assertIn("sourceChecks.removeAll { $0.source == source }",MODEL)
        self.assertIn("agentBay.events.last",UI)
        self.assertIn("checks.count - failures.count",UI)

    def test_pilot_explicitly_invoked_local_and_time_bounded(self):
        part=AGENT.split("func runKnowledgePilot()",1)[1].split("private func finishKnowledgePilot",1)[0]
        self.assertIn("agentBay.runKnowledgePilot()",WORK)
        self.assertIn("K03-06",part)
        self.assertIn("실제 공개 금지",part)
        self.assertIn("humanVerified",part)
        self.assertIn('"--sandbox", "workspace-write"',part)
        self.assertIn("sandbox_workspace_write.network_access=false",part)
        self.assertIn('"-a", "never"',part)
        self.assertIn("workingDirectory: directory",part)
        self.assertIn("Task.sleep(for: .seconds(3600))",part)
        self.assertNotIn("dangerously-bypass",AGENT)
        self.assertIn("agentBay.nightShiftStatus",WORK)

    def test_artifact_status_cannot_claim_published(self):
        self.assertIn("run.hasArtifact($0)",AGENT)
        self.assertIn("code != 0 ? .failed",AGENT)
        self.assertIn("산출물 생성 · 검토 대기",AGENT)
        self.assertIn("values.isSymbolicLink != true",AGENT)
        self.assertIn("latest-run.json",AGENT)
        self.assertIn("실제 발행 성공을 의미하지 않습니다",WORK)
if __name__=="__main__":unittest.main()
