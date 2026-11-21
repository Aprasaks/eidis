"""UI contract: default resting surface is a core with spoken captions only."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
UI=(ROOT/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
CHAT=(ROOT/"macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
PANEL=(ROOT/"macos/Sources/EidisMac/JarvisLiveDialoguePanel.swift").read_text()
class CleanCoreTests(unittest.TestCase):
    def test_resting_caption_does_not_render_technical_status(self):
        caption=UI.split("private func restingCaption",1)[1].split("private var restingControls",1)[0]
        self.assertIn("dialogue.liveTranscript",caption)
        self.assertIn("dialogue.question",caption)
        self.assertIn("dialogue.answer",caption)
        self.assertNotIn("dialogue.status",caption)
        self.assertNotIn("dialogue.streamingAnswer",caption)
        self.assertIn("lineLimit(4)",caption)
        self.assertIn("Task.sleep(for: .seconds(12))",UI)
    def test_no_duplicate_transcript_on_workspace(self):
        self.assertIn("if !commandCenter && !workspaceActive && (showDetails || activeResearch)",UI)
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
