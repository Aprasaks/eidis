"""The user's '자비스' wake must interrupt replies, not wait for the model.
Real-owner microphone and acoustic-echo validation require physical testing.
"""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'macos/Sources/EidisMac'
OVERLAY = (SRC/'JarvisFullscreenOverlay.swift').read_text()
WAKE = (SRC/'JarvisDekaWake.swift').read_text()
CHAT = (SRC/'JarvisOverlayConversation.swift').read_text()
VOICE = (ROOT/'tools/speaker/voice_gate.py').read_text()
MENU = (SRC/'EidisMacApp.swift').read_text()
PERSONA = (SRC/'JarvisPersona.swift').read_text()
CLOCK = (SRC/'JarvisLocalClockAndRouting.swift').read_text()
MODEL = Path.home()/'.jarvis-lab/wakeword/jarvis_en_wake.onnx'

class InterruptibleWake(unittest.TestCase):
    def test_single_wake_word_and_model_selection(self):
        self.assertIn('jarvis_en_wake.onnx', VOICE)
        self.assertIn('jarvis_en_wake.onnx', WAKE)
        self.assertNotIn('aegiya_ko_wake.onnx', VOICE)
        self.assertNotIn('aegiya_ko_wake.onnx', WAKE)
        self.assertIn('WAKEWORD_THRESHOLD = .80', VOICE)
        self.assertIn('ENGLISH_SOLO_THRESHOLD = .75', VOICE)
        self.assertIn('hey_jarvis_v0.1.onnx', VOICE)
        self.assertIn('hey_jarvis_v0.1.onnx', WAKE)
        self.assertNotIn('jarvis_ko_wake.onnx', VOICE)
        self.assertNotIn('jarvis_ko_wake.onnx', WAKE)
        self.assertIn('(0.80...1).contains(score)', WAKE)
        # 학습된 모델 파일은 이 맥의 ~/.jarvis-lab 에만 있다 (저장소·CI에는 없음).
        if MODEL.is_file():
            self.assertGreater(MODEL.stat().st_size, 6000)
        self.assertIn('"Jarvis 상시 대기 켜기"', MENU)
        self.assertIn('"Jarvis 상시 대기 끄기"', MENU)

    def test_resume_wake_while_qwen_or_tts_is_busy(self):
        reconcile = OVERLAY.split('private func reconcileDeka() async {',1)[1].split('private var hotkey:',1)[0]
        self.assertIn('if voice.microphoneCaptureBusy {',reconcile)
        self.assertNotIn('voice.wakeCaptureBusy || greetingTask',reconcile)
        self.assertNotIn('ElevenLabsVoiceService.shared.outputActive',reconcile)
        self.assertIn('await deka.start()',reconcile)
        self.assertIn('voice.onBeforeQuestion = { [weak self] in self?.pauseDeka()',OVERLAY)
        hit=OVERLAY.split('deka.onHit = {',1)[1].split('LocalSpeechListener.beforeCapture',1)[0]
        self.assertNotIn('!voice.wakeCaptureBusy',hit)
        self.assertIn('self.greetingTask?.cancel()',hit)
        self.assertIn('ElevenLabsVoiceService.shared.stopSpeakingNow()',hit)
        self.assertIn('voice.beginDekaWakeTurn()',hit)

    def test_wake_interrupts_before_answering_and_reopens_capture(self):
        path = CHAT.split('func beginDekaWakeTurn() {',1)[1].split('func prepareMiniStandby()',1)[0]
        self.assertIn('if wakeCaptureBusy {',path)
        self.assertIn('interruptCurrentReply()',path)
        self.assertIn('answer = "네, DECHIVE."',path)
        self.assertIn('await self.elevenLabs.speakWakeAcknowledgment(fallback: self.macVoice)',path)
        self.assertIn('await self.elevenLabs.waitForOutputToFinish(fallback: self.macVoice)',path)
        self.assertLess(path.index('speakWakeAcknowledgment(fallback:'),
                        path.index('waitForOutputToFinish(fallback:'))
        self.assertLess(path.index('waitForOutputToFinish(fallback:'),
                        path.index('self.activateListening()'))
        self.assertIn('self.activateListening()',path)
        self.assertNotIn('!wakeCaptureBusy else { return }',path)
        interrupt=CHAT.split('private func interruptCurrentReply() {',1)[1].split('func pauseMicrophone()',1)[0]
        self.assertIn('dialogueTask?.cancel()',interrupt)
        self.assertIn('elevenLabs.stopSpeakingNow()',interrupt)
        self.assertIn('macVoice.stop()',interrupt)
        self.assertIn('generation = UUID()',interrupt)

    def test_already_listening_uses_live_transcript_without_second_engine(self):
        self.assertIn('self.wakeStandbyEnabled, self.isListening,',CHAT)
        self.assertIn('["jarvis", "eidis"].contains(called.lowercased()) || ["자비스", "이디스"].contains(called)',CHAT)
        self.assertIn('self?.beginDekaWakeTurn()',CHAT)
        self.assertIn('var microphoneCaptureBusy: Bool',CHAT)
        self.assertIn('guard names.contains(compact.lowercased()) else { return nil }',CLOCK)
        self.assertIn('"What can I help you with?"',CLOCK)

    def test_persona_is_one_user_requested_address(self):
        self.assertIn('static let preferredAddress = "DECHIVE"',PERSONA)
        self.assertIn("사용자 호칭은 'DECHIVE'입니다",PERSONA)
        self.assertIn('answer = "네, DECHIVE."',CHAT)

    def test_synthetic_model_is_not_misrepresented_as_verified_human_mic(self):
        report = Path.home()/'.jarvis-lab/wakeword/jarvis_ko_experimental_report.json'
        if not report.is_file():   # 실험 보고서는 이 맥에만 있다 (CI에는 없음)
            self.skipTest('local wake-word experiment report not present')
        info=json.loads(report.read_text())
        self.assertIn('synthetic',info['scope'])
        pos=[r for r in info['rows'] if r['positive']]
        neg=[r for r in info['rows'] if not r['positive']]
        self.assertGreaterEqual(sum(x['score']>=.80 for x in pos),1)
        self.assertEqual(sum(x['score']>=.80 for x in neg),0)

if __name__=='__main__':unittest.main()
