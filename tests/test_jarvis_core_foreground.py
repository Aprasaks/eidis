from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
UI=(ROOT/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
ROOM=(ROOT/"macos/Sources/EidisMac/JarvisCommandCenterView.swift").read_text()
class CoreForeground(unittest.TestCase):
    def test_core_is_a_separate_foreground_layer(self):
        self.assertIn(".zIndex(commandCenter ? 9 : 0)",UI)
        self.assertIn("JarvisCommandCenterView(model: liveDashboard, dialogue: dialogue)",UI)
        self.assertIn("jarvis-overview-core-clear-lane",ROOM)
    def test_outer_orbit_is_not_hard_masked(self):
        segment=UI.split("if commandCenter {\n                            // Keep the complete orbit",1)[1].split("} else if compactCore",1)[0]
        self.assertIn("endRadius: overviewCoreSize * 0.50",segment)
        self.assertIn("location: 0.836",segment)
        self.assertIn("location: 0.868",segment)
        self.assertNotIn(".clipShape(Circle())",segment)
if __name__=="__main__": unittest.main()
