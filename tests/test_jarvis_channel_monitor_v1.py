from pathlib import Path
import unittest

SRC = Path(__file__).resolve().parents[1] / "macos/Sources/EidisMac"
MONITOR = (SRC / "JarvisChannelMonitorView.swift").read_text()
CENTER = (SRC / "JarvisCommandCenterView.swift").read_text()


class ChannelMonitorSplit(unittest.TestCase):
    def test_command_center_only_presents_the_monitor(self):
        self.assertIn("JarvisChannelMonitorView(model: model, dialogue: dialogue)", CENTER)
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


if __name__ == "__main__":
    unittest.main()
