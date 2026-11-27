"""블렌더 연출(코어 생성·분해·잔해) 계약."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAC = ROOT / "macos/Sources/EidisMac"


class Cinematics(unittest.TestCase):
    def test_clips_wired(self):
        src = (MAC / "JarvisCinematics.swift").read_text(encoding="utf-8")
        for name in ("DECHIVE_Core_Form", "DECHIVE_Core_Dissolve", "DECHIVE_Debris_Loop"):
            self.assertIn(name, src)
            self.assertIn(name, (ROOT / "macos/scripts/package-app.sh").read_text(encoding="utf-8"))
        self.assertIn("screenBlendMode", src)
        overlay = (MAC / "JarvisFullscreenOverlay.swift").read_text(encoding="utf-8")
        self.assertNotIn("JarvisDebrisBackdrop()", overlay)   # 분해·잔해 연출은 뺐다
        self.assertIn("corePlayback.player.seek(to: .zero)", overlay)

    def test_core_has_no_caption_cut(self):
        overlay = (MAC / "JarvisFullscreenOverlay.swift").read_text(encoding="utf-8")
        self.assertNotIn(".init(color: .clear, location: 0.815)", overlay)

    def test_blender_sources_in_repo(self):
        for f in ("jarvis_hologram.py", "jarvis_dissolve.py", "jarvis_form.py"):
            self.assertTrue((ROOT / "tools/blender" / f).is_file())


class NoShatterOnDashboard(unittest.TestCase):
    """코어→대시보드 전환 때 깨지는(모자이크) 연출은 산만해서 뺐다 (2026-11-27)."""
    def test_mosaic_removed(self):
        self.assertFalse((MAC / "JarvisShardAssembly.swift").exists())
        center = (MAC / "JarvisCommandCenterView.swift").read_text(encoding="utf-8")
        self.assertNotIn("JarvisShardAssembly", center)
        draw = (MAC / "JarvisDrawIn.swift").read_text(encoding="utf-8")
        self.assertNotIn("JarvisShardTiming", draw)
        self.assertIn("accessibilityReduceMotion", draw)


if __name__ == "__main__":
    unittest.main()
