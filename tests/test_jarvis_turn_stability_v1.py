from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]/"macos/Sources/EidisMac"
CHAT=(ROOT/"JarvisOverlayConversation.swift").read_text()
UI=(ROOT/"JarvisFullscreenOverlay.swift").read_text()
VOICE=(ROOT/"ElevenLabsVoiceService.swift").read_text()
class TurnStability(unittest.TestCase):
    def test_idle_mini_promotion_does_not_skip_greeting(self):
        self.assertIn("let continuingActiveTurn = fullscreenDialogue?.wakeCaptureBusy == true",UI)
        self.assertIn("if continuingActiveTurn {",UI)
        self.assertIn("dialogue.showSummonCaption()",UI)
        self.assertIn("fallback.speak(Self.summonGreeting)",VOICE)
    def test_recognizer_stopped_and_missing_partial_time(self):
        self.assertIn("if !self.listener.isListening {\n                    self.completeUtterance()",CHAT)
        self.assertIn("if self.lastPartialAt == nil { self.lastPartialAt = Date() }",CHAT)
        self.assertIn("self.liveTranscript = String(self.listener.transcript.prefix(6000))",CHAT)
    def test_clock_metadata_and_grounded_tasks(self):
        self.assertIn("JarvisLocalClock.context()",CHAT)
        self.assertNotIn("JarvisLocalClock.answer(.both)",CHAT)
        self.assertIn("JarvisDialogueInput.asksTodayTasks(prompt)",CHAT)
        self.assertIn("await dashboard.show()",CHAT)
        self.assertIn("오늘 일정은 아직 연결되지 않았어요",CHAT)
if __name__=="__main__":unittest.main()
