"""UI contract: default resting surface is a core with spoken captions only."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
UI=(ROOT/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
CHAT=(ROOT/"macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
PANEL=(ROOT/"macos/Sources/EidisMac/JarvisLiveDialoguePanel.swift").read_text()
class CleanCoreTests(unittest.TestCase):
    def test_right_dialogue_retained_without_routine_status(self):
        self.assertIn("JarvisLiveDialoguePanel(dialogue: dialogue, quiet: true)",UI)
        self.assertIn("if !quiet {",PANEL)
        self.assertIn("if !quiet && dialogue.dialogueTurns.isEmpty",PANEL)
        self.assertIn("if !dialogue.liveTranscript.isEmpty || (!quiet && dialogue.isListening)",PANEL)
        self.assertIn("Text(turn.content)",PANEL)
        self.assertNotIn("restingCaption(size:",UI)
    def test_no_duplicate_transcript_on_workspace(self):
        self.assertIn("if !commandCenter && !workspaceActive {",UI)
        self.assertIn("workspaceConversationPanel",UI)
    def test_controls_and_diagnostics_remain_accessible(self):
        self.assertIn("controlsHovered || isInputFocused || showDiagnostics || !typedText.isEmpty",UI)
        self.assertIn("private var diagnosticsPanel",UI)
        self.assertIn("Text(dialogue.status)",UI)
        self.assertIn("voicePauseMenu",UI)
        self.assertIn("dialogue.showSummonCaption()",UI)
        self.assertIn("func showSummonCaption()",CHAT)
    def test_sources_remain_available(self):
        self.assertIn("if let source = dialogue.sourceURL",PANEL)
        self.assertIn("destination: source",PANEL)
        self.assertIn("if let source = dialogue.sourceURL",UI)
if __name__=="__main__": unittest.main()
