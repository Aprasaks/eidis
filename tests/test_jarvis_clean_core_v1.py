"""UI contract: default resting surface is a core with spoken captions only."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
UI=(ROOT/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
CHAT=(ROOT/"macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
PANEL=(ROOT/"macos/Sources/EidisMac/JarvisLiveDialoguePanel.swift").read_text()
class CleanCoreTests(unittest.TestCase):
    def test_home_has_no_right_hand_dialogue(self):
        self.assertNotIn("JarvisLiveDialoguePanel(dialogue: dialogue, quiet: true)", UI)
        self.assertIn("if workspaceActive {", UI)
        self.assertNotIn("restingCaption(size:", UI)
        self.assertIn('JarvisLoopingCore(videoURL: videoURL, compact: compactCore,', UI)

    def test_workspace_still_has_conversation_and_data_panels(self):
        self.assertIn("workspaceConversationPanel", UI)
        self.assertIn("if workspaceActive {", UI)
        self.assertIn("JarvisLiveDialoguePanel", PANEL)
        self.assertIn("Text(turn.content)", PANEL)

    def test_diagnostics_still_available_in_workspace_logic(self):
        self.assertIn("private var diagnosticsPanel", UI)
        self.assertIn("Text(dialogue.status)", UI)
        self.assertIn("voicePauseMenu", UI)
        self.assertIn("dialogue.prepareHomeStandby()", UI)
        self.assertIn("func showSummonCaption()", CHAT)

    def test_sources_remain_available(self):
        self.assertIn("if let source = dialogue.sourceURL",PANEL)
        self.assertIn("destination: source",PANEL)
        self.assertIn("if let source = dialogue.sourceURL",UI)
if __name__=="__main__": unittest.main()
