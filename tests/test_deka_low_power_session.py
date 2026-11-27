from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
SW=ROOT/"macos/Sources/EidisMac"
CHAT=(SW/"JarvisOverlayConversation.swift").read_text()
UI=(SW/"JarvisFullscreenOverlay.swift").read_text()
GATE=(ROOT/"tools/speaker/voice_gate.py").read_text()
class LowPowerSession(unittest.TestCase):
    def test_quiet_gate_keeps_preroll_and_tail(self):
        self.assertIn("gate=QuietWake(detector)",GATE)
        self.assertIn("self.history=deque(maxlen=20)",GATE)
        self.assertIn("self.tail=25",GATE)
        self.assertIn("self.skipped+=1",GATE)
        self.assertIn("ncpu=1",GATE)
    def test_relisten_only_after_output_ends(self):
        part=CHAT.split("private func handleQuestion",1)[1].split("private func planAndRespond",1)[0]
        self.assertLess(part.index("await elevenLabs.waitForOutputToFinish"),part.index("if wakeTurn && wakeStandbyEnabled"))
        self.assertIn("localReply?.end != true",part)
        self.assertIn("wakeSessionTurns < 30",part)
        self.assertIn("activateListening()",part)
    def test_inactivity_rejection_disable_ends_session(self):
        self.assertIn("wakeSessionIdle = 12.0",CHAT)
        self.assertIn("self.wakeTurn && elapsed >= self.wakeSessionIdle && self.listener.transcript.isEmpty",CHAT)
        self.assertIn("self.finishMiniTurn()",CHAT)
        self.assertIn("dialogue?.endWakeSession()",UI)
        self.assertIn("miniDialogue?.endWakeSession()",UI)
        self.assertIn("wakeSessionLimit = 600.0",CHAT)
    def test_presence_and_residency(self):
        self.assertIn("JarvisDialogueInput.presenceOrEnd(command)",CHAT)
        self.assertIn('"keep_alive": JarvisLocalModelConfiguration.keepAlive',CHAT)
        self.assertNotRegex(CHAT,r'"num_ctx":\s*\d')
if __name__=="__main__":unittest.main()
