"""Audio-reactive HOME feedback is wired to real, bounded local states."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "macos/Sources/EidisMac"
CORE = (ROOT / "JarvisCoreReactiveEffects.swift").read_text()
METER = (ROOT / "JarvisAudioLevelMeter.swift").read_text()
SPEECH = (ROOT / "NativeSpeech.swift").read_text()
CONVERSATION = (ROOT / "JarvisOverlayConversation.swift").read_text()
WAKE = (ROOT / "JarvisDekaWake.swift").read_text()
ELEVEN = (ROOT / "ElevenLabsVoiceService.swift").read_text()
OVERLAY = (ROOT / "JarvisFullscreenOverlay.swift").read_text()


class ReactiveCore(unittest.TestCase):
    def test_stable_core_playback_excludes_reactive_graphics(self):
        self.assertIn("persistentPlayback: corePlayback", OVERLAY)
        self.assertIn('url(forResource: "DECHIVE_FullHD_Loop"', OVERLAY)
        self.assertNotIn("JarvisCoreReactiveEffects(dialogue:", OVERLAY)
        self.assertIn(".init(color: .white, location: 0.765)", OVERLAY)
        self.assertIn(".init(color: .clear, location: 0.815)", OVERLAY)
        # Experimental assets remain in source, not in the running HOME.
        self.assertIn('wake.status == "호출 대기 · Jarvis"', CORE)

    def test_microphone_meter_reads_live_pcm_only_during_turn(self):
        self.assertIn("AVAudioPCMBuffer", METER)
        self.assertIn("buffer.floatChannelData?[0]", METER)
        self.assertIn("let rms = sqrt(sum / Double(count))", METER)
        self.assertIn("NSLock()", METER)
        self.assertNotIn("FileHandle(", METER)
        self.assertNotIn("URLSession", METER)
        self.assertIn("private let inputMeter = JarvisAudioLevelMeter()", SPEECH)
        self.assertIn("meter.ingest(buffer)", SPEECH)
        self.assertIn("inputMeter.reset()", SPEECH)
        self.assertIn("isListening ? inputMeter.level : 0", SPEECH)
        self.assertIn("listener.inputLevel", CONVERSATION)
        self.assertIn("TimelineView(.animation(minimumInterval: 1.0 / 30.0", CORE)

    def test_output_amplitude_follows_real_elevenlabs_player(self):
        self.assertIn("audio.isMeteringEnabled = true", ELEVEN)
        self.assertIn("player.updateMeters()", ELEVEN)
        self.assertIn("player.averagePower(forChannel: 0)", ELEVEN)
        self.assertIn("ElevenLabsVoiceService.shared.visualOutputAmplitude", CORE)
        self.assertIn("outputAmplitude() ?? 0.52", CORE)
        self.assertIn("reducedMotion", CORE)

    def test_speaking_pulse_starts_only_after_playback_begins(self):
        self.assertIn("@Published private(set) var soundOutputActive = false", CONVERSATION)
        self.assertIn("soundOutputActive = elevenLabs.isPlayingVoice || macVoice.isSpeaking", CONVERSATION)
        self.assertIn("self.soundOutputActive = self.elevenLabs.isPlayingVoice || self.macVoice.isSpeaking", CONVERSATION)
        self.assertIn("self.soundOutputActive = false", CONVERSATION)
        self.assertIn("var isPlayingVoice: Bool { player?.isPlaying == true }", ELEVEN)
        self.assertIn("dialogue.isSpeaking && dialogue.soundOutputActive", CORE)

    def test_wake_flash_is_triggered_only_after_verified_hit(self):
        self.assertIn("activationSequence &+= 1", WAKE)
        self.assertIn('(0.80...1).contains(score)', WAKE)
        self.assertIn("onHit?()", WAKE)
        self.assertIn('voice.beginDekaWakeTurn()', OVERLAY)
        self.assertIn("voice.wakeStandbyEnabled = dekaEnabled", OVERLAY)

    def test_home_standby_does_not_spawn_second_mini(self):
        self.assertIn("let atHomeDesk = JarvisDisplayRoles.hasHouseholdArrangement()", OVERLAY)
        self.assertIn("if !atHomeDesk && !miniEnabled {", OVERLAY)
        self.assertIn('dekaStatus = "HOME 화면 연결 대기 중…"', OVERLAY)
        self.assertIn("if !dekaEnabled && UserDefaults.standard.bool(forKey: dekaPreferenceKey)", OVERLAY)


if __name__ == "__main__":
    unittest.main()
