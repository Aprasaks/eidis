"""JARVIS real-work HUD & core-click navigation without fabricated operations."""
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'macos/Sources/EidisMac'
UI=(BASE/'JarvisCommandCenterView.swift').read_text()
OVERLAY=(BASE/'JarvisFullscreenOverlay.swift').read_text()
AGENTS=(BASE/'JarvisAgentTerminalBay.swift').read_text()
GEO=(BASE/'JarvisOverviewGeometry.swift').read_text()

class ClickableCoreHUD(unittest.TestCase):
    def test_orbit_click_opens_dashboard_without_stt_or_qwen(self):
        segment=OVERLAY.split('// The glowing core is a direct, model-free way',1)[1].split('// No reactive graphics',1)[0]
        self.assertIn('Button {',segment)
        self.assertIn('Task { _ = await liveDashboard.show(.overview) }',segment)
        self.assertIn('if commandCenter {',segment)
        self.assertIn('_ = liveDashboard.hide()',segment)
        self.assertIn('jarvis-core-tap-workroom-toggle',segment)
        self.assertIn('accessibilityLabel(',segment)
        self.assertIn('overviewFrame.midX',segment)
        self.assertIn('.zIndex(11)',segment)
        self.assertIn('.contentShape(Circle())',segment)

    def test_no_second_core_and_side_panels_animate(self):
        self.assertEqual(OVERLAY.count('JarvisLoopingCore(videoURL: videoURL, compact: compactCore,'),1)
        self.assertIn('workspaceRevealed ? 0 : -26',UI)
        self.assertIn('workspaceRevealed ? 0 : 26',UI)
        self.assertIn('JarvisOverviewGeometry.coreFrame',OVERLAY)

    def test_agent_probes_do_not_masquerade_as_active_work(self):
        self.assertIn('if probe { $0.logs = [] }',AGENTS)
        self.assertIn('if !probe {',AGENTS)
        self.assertIn('if runKinds[id] != true',AGENTS)
        self.assertIn('case .ready: "대기"',AGENTS)
        self.assertIn('func probeAll(force: Bool = false)',AGENTS)
        self.assertIn('let laneHeights = Array(repeating: laneHeight',UI)
        self.assertIn('id.workroomAccent',UI)
        self.assertIn('ScrollView(.vertical)',UI)

    def test_live_events_have_real_sources_not_generated_metrics(self):
        segment=UI.split('private func agentEventStream(',1)[1].split('private func macTelemetryCard(',1)[0]
        self.assertIn('agentBay.events',segment)
        self.assertIn('model.sourceChecks',segment)
        self.assertIn('check.at.formatted',segment)
        self.assertIn('$0.detail',segment)
        self.assertIn('현재 AI 작업 실행 없음',segment)
        self.assertNotIn('fake',segment.lower())

    def test_social_youtube_show_real_metadata_and_no_blank_project_cards(self):
        left=UI.split('private func leftColumn(',1)[1].split('private func centerColumn(',1)[0]
        self.assertNotIn('projectsCard(',left)
        self.assertIn('JarvisWorkroomProject.allCases',left)
        self.assertIn('jarvis-channel-overview',left)
        self.assertIn('jarvis-workroom-youtube-recent-and-analytics',UI)
        self.assertIn('광고 집행 · 미연결 (Meta Ads API)',UI)
        self.assertNotIn('CLI --version 실행',UI)
        self.assertIn('readableTime(item.checkedAt)',UI)

if __name__=='__main__':unittest.main()
