"""Dashboard dictation must expose the real microphone without a false status badge."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
UI=(ROOT/'macos/Sources/EidisMac/JarvisCommandCenterView.swift').read_text()
CHAT=(ROOT/'macos/Sources/EidisMac/JarvisOverlayConversation.swift').read_text()
PANEL=(ROOT/'macos/Sources/EidisMac/JarvisLiveDialoguePanel.swift').read_text()
OVERLAY=(ROOT/'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()

class DashboardVoiceStatus(unittest.TestCase):
    def test_actual_speech_transcript_is_displayed_in_visible_composer(self):
        self.assertIn('jarvis-workroom-command-input',UI)
        self.assertIn('dialogue.liveTranscript',UI)
        self.assertIn('setDashboardDictation(true)',UI)
        self.assertIn('setDashboardDictation(false)',UI)
        self.assertIn('TextField("말씀하거나 입력해 주세요…", text: $draftText)', PANEL)
        self.assertIn('.focused($draftFocused)',PANEL)
        self.assertIn('draftFocused && NSApp.isActive ? 0',PANEL)
        self.assertIn('.onChange(of: dialogue.liveTranscript)',PANEL)
        self.assertIn('draftText = transcript',PANEL)
        self.assertIn('jarvis-dashboard-live-composer',PANEL)
        self.assertIn('jarvis-dashboard-dictation-toggle',PANEL)

    def test_voice_status_only_reflects_recognizer_and_has_explicit_pause(self):
        self.assertIn('dialogue.isListening ? "LIVE · 음성 받아쓰기"', PANEL)
        self.assertIn('dialogue.setDashboardDictation(!dialogue.dashboardDictationEnabled)',PANEL)
        self.assertIn('dialogue.dashboardDictationEnabled ? dialogue.status',PANEL)
        self.assertNotIn('voiceStandbyControl(scale: scale)',UI)
        self.assertNotIn('LOCAL CHECKS ONLINE',UI)
        self.assertIn('jarvis-workroom-microphone',UI)

    def test_real_agent_bay_replaces_right_system_card(self):
        right=UI.split('private func rightColumn(',1)[1].split('private func macTelemetryCard(',1)[0]
        self.assertIn('agentTerminalCard(id, scale: scale)',right)
        self.assertIn('agentLaunchControl(scale: scale)',right)
        self.assertIn('agentEventStream(scale: scale)',right)
        self.assertNotIn('systemCard(scale: scale)',right)
        self.assertIn('telemetry.current',UI)
        self.assertIn('jarvis-workroom-center-conversation',UI)

    def test_microphone_is_released_when_leaving_dashboard(self):
        self.assertIn('func setDashboardDictation(_ enabled: Bool)',CHAT)
        self.assertIn('miniSingleTurn || wakeTurn || (wakeStandbyEnabled && !dashboardDictationEnabled)',CHAT)
        self.assertIn('if dashboardDictationEnabled || isActive { activateListening() }',CHAT)
        self.assertIn('else if isListening || listeningTask != nil {',CHAT)
        self.assertIn('pauseMicrophone()',CHAT)
        self.assertIn('if self.dashboardDictationEnabled && !failed &&',CHAT)
        self.assertIn('Self.microphoneAlreadyAuthorized',CHAT)

    def test_no_duplicate_player_or_reactive_effects(self):
        self.assertNotIn('JarvisLoopingCore(',UI)
        self.assertNotIn('JarvisCoreReactiveEffects(',UI)
        self.assertIn('JarvisCommandCenterView(model: liveDashboard, dialogue: dialogue, agentBay: dialogue.agentBay)',OVERLAY)
        self.assertIn('jarvis-workroom-center-conversation',UI)

if __name__=='__main__':
    unittest.main()
