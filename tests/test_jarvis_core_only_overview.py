from pathlib import Path
import unittest
P=Path(__file__).resolve().parents[1]/"macos/Sources/EidisMac"
ROOM=(P/"JarvisCommandCenterView.swift").read_text()
OVER=(P/"JarvisFullscreenOverlay.swift").read_text()
GEOM=(P/"JarvisOverviewGeometry.swift").read_text()
class CoreOnlyOverview(unittest.TestCase):
    def test_center_lane_contains_only_transparent_slot(self):
        part=ROOM.split("private func centerColumn(",1)[1].split("private func rightColumn(",1)[0]
        self.assertIn("Color.clear",part)
        self.assertIn("jarvis-overview-core-clear-lane",part)
        for item in ["Picker(", "DECHIVE CORE / ACTIVE", "activityCard(", "recordedCard(", "RoundedRectangle", "JarvisLiveDialoguePanel"]:
            self.assertNotIn(item,part)
    def test_single_core_and_no_duplicate_bottom_answer(self):
        self.assertIn("JarvisLoopingCore(videoURL: videoURL, compact: compactCore)",OVER)
        self.assertIn("JarvisOverviewGeometry.coreFrame",OVER)
        self.assertNotIn("if commandCenter && (!dialogue.answer.isEmpty",OVER)
        self.assertIn("columnHeight - size",GEOM)
        self.assertNotIn("columnHeight * 0.64",GEOM)
if __name__=="__main__":unittest.main()
