import pathlib, unittest

MAC = pathlib.Path(__file__).resolve().parents[1] / "macos/Sources/EidisMac"


class MissedPostNotice(unittest.TestCase):
    def test_notice_only_never_late_publish(self):
        src = (MAC / "JarvisMissedPostNotice.swift").read_text(encoding="utf-8")
        # 놓친 시간대는 알리기만 하고, 게시 함수는 부르지 않는다
        self.assertNotIn(".publish(", src)
        self.assertIn("NSWorkspace.didWakeNotification", src)
        self.assertIn('guard !UserDefaults.standard.bool(forKey: key) else { return }', src)
        self.assertIn("startMinute: 22 * 60, endMinute: 23 * 60 + 30", src)
        self.assertIn("startMinute: 9 * 60, endMinute: 11 * 60", src)
        runner = (MAC / "JarvisCarouselRunner.swift").read_text(encoding="utf-8")
        self.assertIn("JarvisMissedPostNotice.shared.start()", runner)


if __name__ == "__main__":
    unittest.main()
