"""Fixed Jarvis wake acknowledgement uses configured ElevenLabs, not Mac TTS.

This is a source and flow contract, not a paid API or live microphone test.
"""
from pathlib import Path
import unittest  # 2026-11-27: 영어 대화·Kokoro Heart 음성으로 갱신 (사용자 요청)

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "macos/Sources/EidisMac"
CHAT = (SOURCE / "JarvisOverlayConversation.swift").read_text()
ELEVEN = (SOURCE / "ElevenLabsVoiceService.swift").read_text()


class JarvisElevenlabsWakeContract(unittest.TestCase):
    def test_wake_turn_uses_elevenlabs_voice_and_waits_before_listening(self):
        section = CHAT.split("func beginDekaWakeTurn() {", 1)[1].split(
            "func prepareMiniStandby()", 1)[0]
        self.assertIn('answer = "네 오빠"', section)
        self.assertNotIn('macVoice.speak(answer)', section)
        self.assertIn('await self.elevenLabs.speakWakeAcknowledgment(fallback: self.macVoice)', section)
        self.assertIn('await self.elevenLabs.waitForOutputToFinish(fallback: self.macVoice)', section)
        self.assertIn('try await Task.sleep(for: .milliseconds(250))', section)
        self.assertIn('self.activateListening()', section)
        self.assertLess(section.index('speakWakeAcknowledgment(fallback:'),
                        section.index('waitForOutputToFinish(fallback:'))
        self.assertLess(section.index('waitForOutputToFinish(fallback:'),
                        section.index('self.activateListening()'))
        self.assertIn('guard token == self.generation, !Task.isCancelled else { return }', section)

    def test_wake_acknowledgment_uses_selected_voice_and_opt_in(self):
        section = ELEVEN.split('func speakWakeAcknowledgment(fallback:', 1)[1].split(
            '/// Esc cancels in-flight greeting', 1)[0]
        self.assertIn('private static var wakeAcknowledgment: String { JarvisConversationLanguage.wakeAcknowledgment }', ELEVEN)
        self.assertIn('if !keyPresent { await refreshSavedKeyAvailability() }', section)
        self.assertIn('if enabled, !JarvisKokoroVoice.shared.isPrimary, let cached = wakeAcknowledgmentCache,', section)
        self.assertIn('cached.voiceID == voiceID, cached.modelID == modelID', section)
        self.assertIn('cached.speed == responseSpeed', section)
        self.assertIn('await synthesize(Self.wakeAcknowledgment, fallback: fallback,', section)
        self.assertIn('isWakeAcknowledgment: true', section)
        self.assertIn('guard (enabled || explicitlyPreviewed) && keyPresent else {', ELEVEN)
        self.assertIn('"text": phrase, "model_id": modelID', ELEVEN)
        self.assertIn('https://api.elevenlabs.io/v1/text-to-speech/', ELEVEN)

    def test_caches_fixed_response_without_persisting_audio_or_repeat_credits(self):
        self.assertIn('private var wakeAcknowledgmentCache: (voiceID: String, modelID: String, speed: Double, audio: Data)?', ELEVEN)
        self.assertIn('wakeAcknowledgmentCache = (voiceID: id, modelID: modelID,', ELEVEN)
        self.assertIn('status = "Jarvis 호출 인사 · ElevenLabs 캐시 재생 (추가 크레딧 없음)"', ELEVEN)
        self.assertIn('let audio = try AVAudioPlayer(data: cached.audio)', ELEVEN)
        self.assertIn('audio.play()', ELEVEN)
        self.assertNotIn('defaults.set(wakeAcknowledgmentCache', ELEVEN)
        self.assertNotIn('FileManager.default.createFile', ELEVEN)

    def test_interruption_and_failure_are_safe(self):
        section = ELEVEN.split('func speakWakeAcknowledgment(fallback:', 1)[1].split(
            '/// Esc cancels in-flight greeting', 1)[0]
        self.assertIn('for _ in 0..<12 where isBusy {', section)
        self.assertIn('fallback.speak(Self.wakeAcknowledgment)', section)
        self.assertIn('try await Task.sleep(for: .milliseconds(100))', section)
        self.assertIn('guard !Task.isCancelled else { return }', section)
        self.assertIn('speechGeneration += 1', ELEVEN)
        self.assertIn('guard !Task.isCancelled, generation == speechGeneration else { return }', ELEVEN)

if __name__ == '__main__':
    unittest.main()
