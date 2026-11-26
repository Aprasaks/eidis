from pathlib import Path
import hashlib
import shutil
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path('/Users/demian/Desktop/d9JdnKgJp9BbmaeXXOsp6w.mp4')
ASSET=ROOT/'macos/Resources/Art'
OVERLAY=(ROOT/'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
EFFECT=(ROOT/'macos/Sources/EidisMac/JarvisCoreReactiveEffects.swift').read_text()
PACKAGE=(ROOT/'macos/scripts/package-app.sh').read_text()

class BlenderSplit(unittest.TestCase):
    def test_supplied_footage_exact_sha_when_local_original_is_present(self):
        if SOURCE.is_file():
            digest=hashlib.file_digest(SOURCE.open('rb'), 'sha256').hexdigest()
            self.assertEqual(digest,'a763fd2e6c675812be3ea704d061ca628253692ca3e0801d850618bf2ddb84f5')

    def test_source_segments_preserved_but_not_loaded_for_stable_home(self):
        for name,minimum in [('JARVIS_Core_Idle',900_000),
                             ('JARVIS_Core_Input_Rings',600_000),
                             ('JARVIS_Core_Output_Brush',1_000_000)]:
            path=ASSET/f'{name}.mp4'
            self.assertTrue(path.is_file(),path)
            self.assertGreater(path.stat().st_size,minimum)
        self.assertIn('url(forResource: "DECHIVE_FullHD_Loop"',OVERLAY)
        self.assertNotIn('url(forResource: "JARVIS_Core_Idle"',OVERLAY)
        self.assertNotIn('JarvisCoreReactiveEffects(dialogue:',OVERLAY)
        self.assertIn('rm -f "$RESOURCES/JARVIS_Core_Idle.mp4"',PACKAGE)
        self.assertIn('JARVIS_Core_Input_Rings.mp4',PACKAGE)
        self.assertIn('JARVIS_Core_Output_Brush.mp4',PACKAGE)

    def test_stable_video_is_looped_with_caption_mask(self):
        self.assertIn('AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))',OVERLAY)
        self.assertIn('location: 0.765',OVERLAY)
        self.assertIn('location: 0.815',OVERLAY)
        self.assertIn('persistentPlayback: corePlayback',OVERLAY)

if __name__ == '__main__':unittest.main()
