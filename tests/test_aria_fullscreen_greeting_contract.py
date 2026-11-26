from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = (ROOT / 'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
ELEVEN = (ROOT / 'macos/Sources/EidisMac/ElevenLabsVoiceService.swift').read_text()

class AriaFullscreenGreetingContract(unittest.TestCase):
    def test_quiet_home_does_not_speak_or_take_keyboard_focus(self):
        self.assertIn('dialogue.prepareHomeStandby()', OVERLAY)
        self.assertNotIn('speakSummonGreeting(fallback: self.greetingFallback)', OVERLAY)
        self.assertNotIn('dialogue.showSummonCaption()', OVERLAY)
        self.assertIn('window.orderFrontRegardless()', OVERLAY)
        self.assertNotIn('window.orderFrontRegardless()\n        window.makeKey()', OVERLAY)
        self.assertIn('private static let summonGreeting = "오빠, 뭘 도와드릴까요?"', ELEVEN)
        self.assertIn('if !keyPresent { await refreshSavedKeyAvailability() }', ELEVEN)
        self.assertNotIn('SFSpeechRecognizer', OVERLAY)

    def test_cancel_on_escape_and_termination(self):
        self.assertIn('if event.keyCode == 53', OVERLAY)
        self.assertIn('greetingTask?.cancel()', OVERLAY)
        self.assertGreaterEqual(OVERLAY.count('ElevenLabsVoiceService.shared.stopSpeakingNow()'), 2)
        self.assertIn('greetingFallback.stop()', OVERLAY)
        self.assertIn('guard !Task.isCancelled, generation == speechGeneration else { return }', ELEVEN)
        self.assertIn('speechGeneration += 1', ELEVEN)
    def test_opt_in_and_cache_fixed_greeting(self):
        self.assertIn('if enabled, let cached = greetingCache', ELEVEN)
        self.assertIn('greetingCache = (voiceID: id, modelID: modelID, audio: data)', ELEVEN)
        self.assertIn('enabled || explicitlyPreviewed', ELEVEN)
        self.assertNotIn('private static let maxRequests = 5', ELEVEN)
        self.assertIn('status = "소환 인사 재생 중 · 저장된 오디오 재사용 (추가 크레딧 없음)"', ELEVEN)
        self.assertIn('fallback.speak(phrase, rateOverride: isSummonGreeting ? Self.summonFallbackRate : nil)', ELEVEN)

if __name__ == '__main__': unittest.main()
