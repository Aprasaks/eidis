from pathlib import Path
import unittest

META = (Path(__file__).resolve().parents[1] / "macos/Sources/EidisMac/JarvisMetaChannels.swift").read_text()


class ThreadsMetricsAndFailureStates(unittest.TestCase):
    def test_threads_followers_come_from_insights_api(self):
        self.assertIn("graph.threads.net/v1.0/me/threads_insights?metric=followers_count", META)
        self.assertIn("followersCount: await followers", META)

    def test_threads_post_count_is_exact_or_unknown(self):
        body = META.split("func threadsPostCount(", 1)[1].split("func tokenFree(", 1)[0]
        self.assertIn("return next == nil ? total : nil", body)
        self.assertIn('url.host == "graph.threads.net"', body)

    def test_paging_links_never_carry_token_in_url(self):
        body = META.split("func tokenFree(", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn('$0.name != "access_token"', body)

    def test_failure_kinds_are_distinct(self):
        body = META.split("func failureKind(", 1)[1].split("\n    }\n", 1)[0]
        for text in ("인증 만료", "권한 부족", "호출 한도 초과", "Meta 서버 일시 오류"):
            self.assertIn(text, body)
        self.assertIn("case 190", body)

    def test_optional_metrics_do_not_mark_account_disconnected(self):
        verify = META.split("func verifyThreads(", 1)[1].split("func scanFacebook(", 1)[0]
        self.assertIn('return .init(connected: true, handle: "@dechive.wiki"', verify)


if __name__ == "__main__":
    unittest.main()
