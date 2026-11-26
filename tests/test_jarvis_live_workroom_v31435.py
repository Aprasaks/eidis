"""Workroom contract: real local sources, voice overlay and explicit CLI execution."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "macos/Sources/EidisMac"
UI = (SRC / "JarvisCommandCenterView.swift").read_text()
# The SNS / YouTube channel monitor moved to its own file; check both.
UI += "\n" + (SRC / "JarvisChannelMonitorView.swift").read_text()
AGENTS = (SRC / "JarvisAgentTerminalBay.swift").read_text()
ROUTE = (SRC / "JarvisLiveDashboard.swift").read_text()
OVERLAY = (SRC / "JarvisFullscreenOverlay.swift").read_text()

class LiveWorkroomContract(unittest.TestCase):
    def test_no_generic_header_or_project_metrics_in_visible_workroom(self):
        visible = UI.split('var body: some View {',1)[1].split('private func leftColumn(',1)[0]
        self.assertNotIn('header(scale:', visible)
        self.assertNotIn('keyMetrics(scale:', visible)
        self.assertNotIn('projectsCard(scale:', visible)
        self.assertIn('jarvis-command-center-close', visible)
        left = UI.split('private func leftColumn(',1)[1].split('private func centerColumn(',1)[0]
        self.assertIn('JarvisWorkroomProject.allCases', left)
        self.assertIn('showChannelOverview = true', left)
        self.assertNotIn('projectsCard(scale:', left)
        self.assertIn('metaCard(scale: 1.1)', UI)
        self.assertIn('youtubeCard(scale: 1.1)', UI)

    def test_youtube_expanded_area_is_backed_by_real_api_data(self):
        youtube = UI.split('private func youtubeCard(',1)[1].split('private func knowledgeCard(',1)[0]
        self.assertIn('item.analytics', youtube)
        self.assertIn('item.recentVideos', youtube)
        self.assertIn('item.checkedAt', youtube)
        self.assertIn('item.analyticsError', youtube)
        self.assertIn('item.recentVideosError', youtube)

    def test_command_router_opens_and_closes_workroom(self):
        self.assertIn('"작업실"', ROUTE)
        self.assertIn('if workroom && close { return .hide }', ROUTE)
        self.assertIn('return .show(.overview)', ROUTE)

    def test_core_single_and_side_panels_animated(self):
        self.assertIn("JarvisOverviewGeometry.coreFrame", OVERLAY)
        self.assertNotIn("JarvisLoopingCore(", UI)
        self.assertIn("workspaceRevealed ? 0 : -26", UI)
        self.assertIn("workspaceRevealed ? 0 : 26", UI)
        self.assertIn("jarvis-agent-terminal-bay", UI)
        self.assertIn("dialogue.liveTranscript", UI)
        self.assertIn("dialogue.streamingAnswer", UI)

    def test_cli_runs_are_real_and_only_user_approved(self):
        self.assertIn("process.executableURL = URL(fileURLWithPath: executable)", AGENTS)
        self.assertIn("process.standardOutput = output", AGENTS)
        self.assertIn("process.standardError = output", AGENTS)
        self.assertIn("output.fileHandleForReading.readabilityHandler", AGENTS)
        self.assertIn("process.terminationHandler", AGENTS)
        self.assertIn('arguments: ["--version"], isProbe: true', AGENTS)
        self.assertIn('func runReadOnly(', AGENTS)
        self.assertIn('agentBay.runReadOnly(selectedAgent, prompt: agentPrompt)', UI)
        self.assertIn('jarvis-agent-start-readonly', UI)
        self.assertIn('func cancel(', AGENTS)
        self.assertIn('process.terminate()', AGENTS)
        self.assertNotIn('/bin/sh', AGENTS)
        self.assertNotIn('/bin/zsh', AGENTS)
        self.assertNotIn('dangerously-bypass', AGENTS)

    def test_llm_external_work_has_read_only_permissions(self):
        self.assertIn('"--permission-mode", "plan"', AGENTS)
        self.assertIn('"--approval-mode", "plan"', AGENTS)
        self.assertIn('"--sandbox", "read-only"', AGENTS)
        self.assertIn("사용자 요청 시 실행 · 읽기 전용", UI)
        self.assertIn("광고 집행 · 미연결 (Meta Ads API)", UI)

    def test_live_logs_are_bounded_and_real(self):
        self.assertIn("if $0.logs.count > 90", AGENTS)
        self.assertIn("if events.count > 60", AGENTS)
        self.assertIn("readableLine(", AGENTS)
        self.assertIn("runKinds[id] = isProbe", AGENTS)
        self.assertIn("lastExitCode", AGENTS)
        self.assertIn('item["message"] as? String', AGENTS)
        self.assertIn('detail["message"] as? String', AGENTS)
        self.assertIn('프로세스 종료 · 코드 ', AGENTS)

if __name__ == "__main__":
    unittest.main()
