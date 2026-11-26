from pathlib import Path
import unittest
P=Path(__file__).resolve().parents[1]/"macos/Sources/EidisMac"
ROOM=(P/"JarvisCommandCenterView.swift").read_text()
OVER=(P/"JarvisFullscreenOverlay.swift").read_text()
GEOM=(P/"JarvisOverviewGeometry.swift").read_text()
class CoreOnlyOverview(unittest.TestCase):
    def test_center_lane_overlays_real_speech_without_second_video_player(self):
        part=ROOM.split("private func centerColumn(",1)[1].split("private func rightColumn(",1)[0]
        self.assertIn('jarvis-workroom-center-conversation',part)
        self.assertIn('dialogue.liveTranscript',part)
        self.assertIn('dialogue.streamingAnswer',part)
        self.assertIn('dialogue.dialogueTurns',part)
        self.assertIn('jarvis-workroom-command-input',part)
        self.assertIn('dialogue.submitTyped(message)',part)
        self.assertNotIn('JarvisLoopingCore(',part)
        self.assertNotIn('fake',part.lower())
    def test_single_core_and_no_duplicate_bottom_answer(self):
        self.assertIn("JarvisLoopingCore(videoURL: videoURL, compact: compactCore,",OVER)
        self.assertIn("JarvisOverviewGeometry.coreFrame",OVER)
        self.assertNotIn("if commandCenter && (!dialogue.answer.isEmpty",OVER)
        self.assertIn("columnHeight - size",GEOM)
        self.assertNotIn("columnHeight * 0.64",GEOM)
if __name__=="__main__":unittest.main()
