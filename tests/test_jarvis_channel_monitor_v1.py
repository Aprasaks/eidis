from pathlib import Path
import unittest

SRC = Path(__file__).resolve().parents[1] / "macos/Sources/EidisMac"
MONITOR = (SRC / "JarvisChannelMonitorView.swift").read_text()
CENTER = (SRC / "JarvisCommandCenterView.swift").read_text()


class ChannelMonitorSplit(unittest.TestCase):
    def test_command_center_only_presents_the_monitor(self):
        self.assertIn("JarvisChannelMonitorView(model: model, dialogue: dialogue, agentBay: agentBay)", CENTER)
        self.assertNotIn(".sheet(isPresented: $showChannelOverview)", CENTER)
        self.assertIn("model.workroomProject == nil && !showChannelOverview", CENTER)
        for moved in ("private func metaCard(", "private func youtubeCard(", "refreshMetaAccounts",
                      "showThreadsConnectionSheet", "JarvisWikiSocialStudio()"):
            self.assertNotIn(moved, CENTER)

    def test_global_and_domestic_channels_are_labelled_apart(self):
        meta = MONITOR.split("private func metaCard(", 1)[1].split("private func youtubeCard(", 1)[0]
        youtube = MONITOR.split("private func youtubeCard(", 1)[1]
        self.assertIn('regionBadge("GLOBAL · 영어권"', meta)
        self.assertIn('regionBadge("DECHIVE · 국내 · 한국어"', youtube)

    def test_states_are_distinct_and_never_claim_connection_without_api(self):
        state = MONITOR.split("private func channelState(", 1)[1].split("private func regionBadge(", 1)[0]
        self.assertIn('if connected { return .init(label: "● 연결됨" + time', state)
        for kind in ("인증 만료", "권한 부족", "호출 한도 초과", "조회 불가 · 네트워크", "미연결 · 토큰 연결 필요"):
            self.assertIn(kind, state)
        self.assertIn('" 확인"', state)

    def test_manual_refresh_and_tokens_stay_masked(self):
        self.assertIn("jarvis-channel-monitor-refresh", MONITOR)
        self.assertIn("guard !metaRefreshing", MONITOR)
        self.assertNotIn("TextField(\"Threads User Access Token\"", MONITOR)
        self.assertIn("SecureField(\"Threads User Access Token\"", MONITOR)

    def test_claude_lane_is_read_only_and_gets_no_tokens(self):
        studio = MONITOR.split("private func claudeStudio(", 1)[1].split("private func refreshAll(", 1)[0]
        self.assertIn("agentBay.runReadOnly(.claude", MONITOR)
        self.assertIn("agentBay.nightShiftRunning", studio)
        summary = MONITOR.split("private func verifiedSummary(", 1)[1].split("private func runClaude(", 1)[0]
        self.assertNotIn("readToken", summary)
        self.assertNotIn("Token", summary)
        self.assertIn("prefix(500 - request.count)", MONITOR)
        self.assertIn("해외 영어권 팔로워만", MONITOR)

    def test_workroom_is_full_size_and_escape_closes(self):
        self.assertIn('"jarvis-sns-workroom"', MONITOR)
        self.assertIn(".keyboardShortcut(.escape, modifiers: [])", MONITOR)
        self.assertIn("CLAUDE CODE / SNS STUDIO", MONITOR)

    def test_operations_room_uses_only_real_sources(self):
        for ident in ("jarvis-sns-kpi-strip", "jarvis-sns-today-routine", "jarvis-sns-published-feed",
                      "jarvis-sns-world-clock", "jarvis-sns-claude-raw-toggle"):
            self.assertIn(ident, MONITOR)
        refresh = MONITOR.split("private func refreshAll(", 1)[1]
        self.assertIn("JarvisMetaInstagramService.recentVerifiedPosts()", refresh)
        self.assertIn("JarvisMetaChannels.recentVerifiedPosts(.threads)", refresh)
        kpi = MONITOR.split("private func kpiStrip(", 1)[1].split("private func checklistRow(", 1)[0]
        self.assertIn('knownFollowers.isEmpty ? "—"', kpi)
        self.assertNotIn("random", kpi.lower())

    def test_briefing_shows_only_real_result_line(self):
        body = MONITOR.split("private func latestBriefing(", 1)[1].split("private func markdown(", 1)[0]
        self.assertIn('lane.state == .completed', body)
        self.assertIn('$0.hasPrefix("[result] ")', body)

    def test_auto_refresh_stops_when_closed(self):
        self.assertIn("Task.sleep(for: .seconds(300))", MONITOR)
        self.assertIn("while !Task.isCancelled", MONITOR)


if __name__ == "__main__":
    unittest.main()
