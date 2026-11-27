"""성장 기록 · Threads 자동 게시 · 살아 있는 코어 계약 (소스 텍스트 기준)."""
import pathlib
import unittest

MAC = pathlib.Path(__file__).resolve().parents[1] / "macos/Sources/EidisMac"


def read(name):
    return (MAC / name).read_text(encoding="utf-8")


class GrowthThreadsCore(unittest.TestCase):
    def test_growth_log_real_values_only(self):
        src = read("JarvisGrowthLog.swift")
        self.assertIn(".jarvis-lab/growth/daily.json", src)
        self.assertIn("row.forEach { today[$0.key] = $0.value }", src)   # 실패 항목은 이전 값 유지
        self.assertIn("guard !row.isEmpty else { return }", src)
        self.assertIn("keyDecodingStrategy = .convertFromSnakeCase", src)

    def test_threads_only_approved_digest_and_once(self):
        src = read("JarvisThreadsPublisher.swift")
        self.assertIn("JarvisCarouselRunner.contentDigest(of: dir) == approved", src)
        self.assertIn("(9 * 60 ..< 11 * 60).contains(minutes)", src)
        self.assertIn('Self.record(dir)?["result"] as? String == "publishing"', src)
        self.assertIn('req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")', src)
        self.assertIn("text.count <= 500", src)
        runner = read("JarvisCarouselRunner.swift")
        self.assertIn('dir.appendingPathComponent("threads.txt")', runner)
        self.assertIn("## threads.txt", runner)

    def test_core_aura_reflects_real_activity_only(self):
        src = read("JarvisCoreAura.swift")
        self.assertIn("agentBay.lane($0).state == .running", src)
        self.assertIn("return nil", src)
        self.assertIn("JarvisCoreAura(agentBay: dialogue.agentBay", read("JarvisFullscreenOverlay.swift"))


if __name__ == "__main__":
    unittest.main()
