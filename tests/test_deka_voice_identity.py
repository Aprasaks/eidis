from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
SWIFT=ROOT/"macos/Sources/EidisMac"
CHAT=(SWIFT/"JarvisOverlayConversation.swift").read_text()
STT=(SWIFT/"NativeSpeech.swift").read_text()
WAKE=(SWIFT/"JarvisDekaWake.swift").read_text()
GATE=(ROOT/"tools/speaker/voice_gate.py").read_text()
class SpeakerGate(unittest.TestCase):
    def test_gate_before_greeting(self):
        self.assertIn('JarvisVoiceIdentity.worker',WAKE)
        self.assertIn('"wake"]',WAKE)
        self.assertIn('line == "REJECT"',WAKE)
        self.assertLess(GATE.index("if accepted:"),GATE.index('print(f"HIT'))
        self.assertIn("deque(maxlen=20)",GATE)
    def test_gate_before_any_command_dispatch_including_recovered_text(self):
        self.assertIn('self.listener.requiresOwnerVoice = self.wakeTurn || self.wakeStandbyEnabled',CHAT)
        part=CHAT.split("func completeUtterance()",1)[1].split("func submitTyped",1)[0]
        self.assertLess(part.index("let recovered"),part.index("JarvisVoiceIdentity.verify"))
        self.assertLess(part.index("JarvisVoiceIdentity.verify"),part.index("await self.handleQuestion"))
        self.assertIn("if !verified",part)
        self.assertIn("self.finishMiniTurn()",part)
        self.assertIn("capture?.append(buffer)",STT)
    def test_no_bypass_or_unbounded_capture(self):
        self.assertIn("owner=load_profile()",GATE)
        self.assertIn("WAKE_THRESHOLD = .25",GATE)
        self.assertIn("COMMAND_THRESHOLD = .52",GATE)
        self.assertIn("SR*2*120+2",GATE)
        self.assertIn("voiceIDCapture?.discard()",STT)
if __name__=="__main__":unittest.main()
