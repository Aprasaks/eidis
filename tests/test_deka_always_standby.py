"""Source-level integration guards; live microphone and timing require real hardware."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]/"macos/Sources/EidisMac"
UI=(ROOT/"JarvisFullscreenOverlay.swift").read_text()
WAKE=(ROOT/"JarvisDekaWake.swift").read_text()
CHAT=(ROOT/"JarvisOverlayConversation.swift").read_text()
MENU=(ROOT/"EidisMacApp.swift").read_text()
class DekaStandby(unittest.TestCase):
    def test_session_opt_in_and_no_three_minute_limit(self):
        self.assertIn("var dekaEnabled = false",UI)
        self.assertIn("Jarvis 상시 대기 켜기",MENU)
        self.assertIn("Jarvis 상시 대기 끄기",MENU)
        self.assertNotIn("seconds(180)",WAKE)
        self.assertIn("seconds(45)",WAKE)
    def test_wake_survives_thinking_and_speaking(self):
        self.assertIn("if voice.microphoneCaptureBusy {", UI)
        self.assertNotIn("voice.wakeCaptureBusy || greetingTask != nil", UI)
        self.assertNotIn("greetingFallback.isSpeaking || ElevenLabsVoiceService.shared.outputActive", UI)
        self.assertIn("LocalSpeechListener.beforeCapture = { [weak self] in self?.pauseDeka(", UI)
        self.assertIn("voice.onBeforeQuestion = { [weak self] in self?.pauseDeka() }", UI)
        self.assertIn("Date() >= dekaNotBefore, !deka.armed", UI)
        self.assertIn("await deka.start()", UI)
        self.assertLess(WAKE.index('stop("Jarvis 감지'), WAKE.index("onHit?()"))
        self.assertIn("self.greetingTask?.cancel()", UI)
        self.assertIn("voice.beginDekaWakeTurn()", UI)

    def test_both_windows_return_to_standby(self):
        self.assertIn("let voice=self.dialogue ?? self.miniDialogue",UI)
        self.assertIn("bindDeka(voice)",UI)
        self.assertIn("bindDeka(dialogue)",UI)
        self.assertIn("miniSingleTurn || wakeTurn || (wakeStandbyEnabled && !dashboardDictationEnabled)",CHAT)
        self.assertIn("guard miniSingleTurn || wakeStandbyEnabled else { return }",CHAT)
        self.assertIn("if wakeCaptureBusy {",CHAT)
        self.assertIn("interruptCurrentReply()",CHAT)
        self.assertIn('answer = "네 오빠"', CHAT)
        self.assertIn("if self.singleTurnCapture {",CHAT)
        self.assertIn("if singleTurnCapture {",CHAT)
        self.assertIn("if wakeStandbyEnabled {",CHAT)
    def test_stop_fail_closed(self):
        self.assertIn("dekaMonitorTask?.cancel()",UI)
        self.assertIn("dekaEnabled = false",UI)
        self.assertIn("deka.onFailure = { [weak self] reason in self?.stopDeka(reason) }",UI)
        self.assertIn("절전으로 상시 대기 일시정지",UI)
        self.assertIn("func stop() {\n        closeDetachedChat()\n        dialogue?.onCasualChatModeChanged = nil\n        stopDeka()",UI)
        self.assertIn("engine.inputNode.removeTap",WAKE)
        self.assertIn("epoch = UUID()",WAKE)
if __name__=="__main__":unittest.main()
