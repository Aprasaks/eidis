from pathlib import Path
import unittest
S=Path(__file__).resolve().parents[1]/"macos/Sources/EidisMac"
OVER=(S/"JarvisFullscreenOverlay.swift").read_text()
CENTER=(S/"JarvisCommandCenterView.swift").read_text()
class CoreCrop(unittest.TestCase):
    def test_only_caption_strip_masked_in_command_center(self):
        mask=OVER.split(".mask {",1)[1] if False else OVER.split("if commandCenter {\n                            // The ring",1)[1].split("} else if compactCore",1)[0]
        self.assertIn("location: 0.835",mask)
        self.assertIn("location: 0.855",mask)
        self.assertNotIn("clipShape(Circle())",mask)
    def test_center_fits_shared_left_slot(self):
        self.assertIn("coreOuter + coreColumnWidth / 2",OVER)
        self.assertIn("12 + coreSlotHeight / 2",OVER)
        self.assertIn("min(coreColumnWidth - 20, coreSlotHeight - 12)",OVER)
        self.assertIn("fullHeight * 0.465",CENTER)
        for w,h in [(800,600),(1512,982),(1920,1080),(2560,1080),(3840,2160)]:
            outer=min(32,max(12,w*.015));left=(w-2*outer)*(.265 if w>=1120 else .27)
            slot=h*.465;d=max(0,min(left-20,slot-12))
            self.assertLessEqual(d,left)
            self.assertLessEqual(d,slot)
if __name__=="__main__":unittest.main()
