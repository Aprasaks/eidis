"""Behavior contract for JARVIS live turn taking; microphone is hardware-tested separately."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
SPEECH = (ROOT / "macos/Sources/EidisMac/NativeSpeech.swift").read_text()
OVERLAY = (ROOT / "macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
PANEL = (ROOT / "macos/Sources/EidisMac/JarvisLiveDialoguePanel.swift").read_text()
ROOM = (ROOT / "macos/Sources/EidisMac/JarvisCommandCenterView.swift").read_text()


class JarvisLiveDialogueContract(unittest.TestCase):
    def test_partial_transcription_is_actual_on_device_audio(self):
        for value in ('shouldReportPartialResults = true',
                      'requiresOnDeviceRecognition = true',
                      'self.transcript = result.bestTranscription.formattedString'):
            self.assertIn(value, SPEECH)
        for value in ('listener.$transcript.sink', 'liveTranscript = String(partial.prefix(6000))',
                      'lastPartialAt = Date()', 'YOU / LIVE TRANSCRIPT',
                      '인식 중 · 아직 확정되지 않은 문장'):
            self.assertIn(value, CHAT + PANEL)
        self.assertNotIn('prediction =', PANEL)
        self.assertNotIn('predictedText', CHAT)

    def test_auto_finish_is_bounded_and_can_be_turned_off(self):
        for value in ('startSilenceDetection(token: token)',
                      'self.autoTurnEnabled',
                      'Date().timeIntervalSince(lastPartialAt) >= self.silenceWaitSeconds',
                      'self.completeUtterance()', 'silenceTask?.cancel()',
                      'func pauseMicrophone()', 'listener.cancel()'):
            self.assertIn(value, CHAT)
        self.assertIn('Toggle(isOn: $dialogue.autoTurnEnabled)', PANEL)
        self.assertIn('dialogue.pauseMicrophone()', PANEL)

    def test_while_speaking_press_space_stops_audio_and_opens_mic(self):
        for value in ('if isThinking || isSpeaking {', 'interruptCurrentReply()',
                      'elevenLabs.stopSpeakingNow()', 'macVoice.stop()',
                      'generation = UUID()', 'dialogueTask?.cancel()',
                      'activateListening()'):
            self.assertIn(value, CHAT)
        self.assertIn('dialogue.toggleMicrophone()', OVERLAY)
        self.assertIn('self.dialogue?.toggleMicrophone()', OVERLAY)
        self.assertIn('dialogue.isSpeaking ? "끼어들기"', OVERLAY)
        self.assertIn('응답 중단 · 내가 말하기', PANEL)
        self.assertNotIn('.disabled(dialogue.isThinking || dialogue.isSpeaking)', OVERLAY)

    def test_session_context_and_core_dashboard_survive(self):
        for value in ('conversation.suffix(8)', 'conversation.count > 8',
                      'dialogueTurns.append(JarvisLiveDialogueTurn(role: "YOU"',
                      'dialogueTurns.append(JarvisLiveDialogueTurn(role: "JARVIS"',
                      'dialogueTurns.removeAll()', 'private let elevenLabs'):
            self.assertIn(value, CHAT)
        self.assertIn('JarvisLiveDialoguePanel(dialogue: dialogue)', OVERLAY)
        self.assertIn('JarvisLiveDialoguePanel(dialogue: dialogue)', ROOM)
        self.assertIn('activityCard(scale: scale)', ROOM)
        self.assertIn('JarvisLoopingCore(videoURL: videoURL, compact: commandCenter)', OVERLAY)
        self.assertIn('jarvis-live-dialogue-panel', PANEL)
        self.assertIn('window.orderOut(nil)', OVERLAY)


if __name__ == "__main__":
    unittest.main()
