"""SNS 아이폰 연동 계약 테스트 (소스 텍스트 기준).

- Mac은 인증된 연결로 들어온 SNS 요청만 JarvisSocialRemote에 넘긴다.
- 승인은 아이폰이 본 버전의 digest가 일치할 때만 기록되고, 게시는 하지 않는다.
- 토큰이나 원본 파일 경로는 아이폰으로 보내지 않는다.
"""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAC = ROOT / "macos/Sources/EidisMac"
IOS = ROOT / "ios/JARVIS/Sources"


def read(path):
    return path.read_text(encoding="utf-8")


class SnsPhoneLinkTests(unittest.TestCase):
    def test_mac_routes_social_kinds_through_existing_auth(self):
        src = read(MAC / "JarvisMacNearbyCalendar.swift")
        self.assertIn("JarvisSocialRemote.remoteKinds.contains(kind)", src)
        self.assertIn('remoteKinds: Set<String> = ["socialSnapshotRequest", "approveSocialPost", "registerPushToken", JarvisPlanRemote.requestKind, JarvisPhoneChat.requestKind, JarvisStockBoard.phoneRequestKind, JarvisPhoneLearning.requestKind, JarvisSNSPause.requestKind]',
                      read(MAC / "JarvisSocialRemote.swift"))
        self.assertIn("JarvisSocialRemote.snapshot(requestID: id)", src)
        self.assertIn("JarvisSocialRemote.decide(request, requestID: id)", src)
        # 근거리 처리도 authorized 검사 이후에 있어야 한다.
        handle = src[src.index("private func handle(_ bytes: Data"):]
        self.assertLess(handle.index("guard authorized.contains(remote) else { return }"),
                        handle.index('kind == "socialSnapshotRequest"'))

    def test_mac_snapshot_sends_no_tokens_or_paths(self):
        src = read(MAC / "JarvisSocialRemote.swift")
        for banned in ("access_token", "Keychain", "runDirectory\":", "\"path\""):
            self.assertNotIn(banned, src)
        self.assertIn("previewBudget = 330_000", src)
        self.assertIn('"digest": digest', src)

    def test_approval_is_digest_bound_and_never_publishes(self):
        src = read(MAC / "JarvisCarouselRunner.swift")
        self.assertIn("func recordOwnerDecision(runID: String, digest: String, approve: Bool)", src)
        self.assertIn("current == digest else { return .changed }", src)
        self.assertIn('saved.status == "review" else { return .notReviewable }', src)
        self.assertIn('"^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$"', src)
        decide = read(MAC / "JarvisSocialRemote.swift")
        self.assertIn('object["ownerApproved"] as? Bool == true', decide)
        self.assertNotIn("graph.facebook.com", decide)

    def test_decided_runs_are_not_remade(self):
        src = read(MAC / "JarvisCarouselRunner.swift")
        self.assertIn('finishedStatuses: Set<String> = ["review", "approved", "rejected", "posted"]', src)

    def test_iphone_social_page_and_requests(self):
        nearby = read(IOS / "JARVISMobileNearbyCalendar.swift")
        self.assertIn('"kind": "socialSnapshotRequest"', nearby)
        self.assertIn('"kind": "approveSocialPost"', nearby)
        self.assertIn('"digest": carousel.digest', nearby)
        self.assertIn('remote["sentAt"] = Date().timeIntervalSince1970', nearby)
        page = read(IOS / "JARVISMobileDashboardView.swift")
        self.assertIn("JARVISMobileSocialView(nearby: nearby)", page)
        view = read(IOS / "JARVISMobileSocialView.swift")
        self.assertIn("confirmationDialog", view)
        project = read(ROOT / "ios/JARVIS.xcodeproj/project.pbxproj")
        self.assertEqual(project.count("JARVISMobileSocialView.swift in Sources"), 2)


if __name__ == "__main__":
    unittest.main()
