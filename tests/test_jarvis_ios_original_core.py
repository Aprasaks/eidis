"""Regression: mobile home uses the REAL Mac fullscreen core, not a substitute."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OriginalCoreContractTests(unittest.TestCase):
    def test_mac_overlay_original_source_and_video_are_present(self):
        original = ROOT / "macos/Resources/Art/DECHIVE_FullHD_Loop.mp4"
        self.assertGreater(original.stat().st_size, 1_000_000)
        overlay = (ROOT / "macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
        self.assertIn('forResource: "DECHIVE_FullHD_Loop"', overlay)
        self.assertIn('AVPlayerLooper', overlay)

    def test_ios_plays_mobile_crop_from_actual_mac_animation(self):
        video = ROOT / "ios/JARVIS/Resources/DECHIVE_Core_Mobile.mp4"
        self.assertGreater(video.stat().st_size, 1_000_000)
        source = (ROOT / "ios/JARVIS/Sources/JARVISHomeView.swift").read_text()
        adapter = (ROOT / "ios/JARVIS/Sources/JarvisLoopingCoreMobile.swift").read_text()
        project = (ROOT / "ios/JARVIS.xcodeproj/project.pbxproj").read_text()
        self.assertIn('JarvisLoopingCoreMobile(videoURL: videoURL, active: active)', source)
        self.assertIn('forResource: "DECHIVE_Core_Mobile"', source)
        self.assertIn('AVPlayerLooper', adapter)
        self.assertIn('DECHIVE_Core_Mobile.mp4 in Resources', project)
        self.assertNotIn('JarvisHologramMobileView', source)
        self.assertNotIn('JarvisHologramMobileView', project)

    def test_mobile_crop_is_documented_and_not_fabricated(self):
        readme = (ROOT / "ios/README.md").read_text()
        self.assertIn("'crop=920:920:500:0'", readme)
        self.assertIn('macos/Resources/Art/DECHIVE_FullHD_Loop.mp4', readme)
        self.assertIn('not native iPhone SceneKit geometry', readme)


if __name__ == '__main__':
    unittest.main()
