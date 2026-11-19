from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = (ROOT / 'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
ELEVEN = (ROOT / 'macos/Sources/EidisMac/ElevenLabsVoiceService.swift').read_text()

class AriaFullscreenGreetingContract(unittest.TestCase):
    def test_greeting_on_manual_summon_only(self):
        self.assertIn('speakSummonGreeting(fallback: self.greetingFallback)', OVERLAY)
        self.assertIn('let greetingFallback = JarvisVoiceService()', OVERLAY)
        self.assertIn('window.orderFrontRegardless()', OVERLAY)
        self.assertLess(OVERLAY.index('window.orderFrontRegardless()\n        window.makeKey()'),
                        OVERLAY.index('speakSummonGreeting(fallback: self.greetingFallback)'))
        self.assertIn('private static let summonGreeting = "네, 자비스입니다."', ELEVEN)
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
        self.assertIn('fallback.speak(phrase)', ELEVEN)

if __name__ == '__main__': unittest.main()
