from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / 'macos/Sources/EidisMac/EidisMacApp.swift').read_text()
LIB = (ROOT / 'macos/Sources/EidisMac/JarvisElevenLabsLibraryView.swift').read_text()
SERVICE = (ROOT / 'macos/Sources/EidisMac/ElevenLabsVoiceService.swift').read_text()

class ElevenLabsLibraryContract(unittest.TestCase):
    def test_library_is_read_only_and_manual(self):
        for marker in ('https://api.elevenlabs.io/v2/voices', 'request.httpMethod = "GET"',
                       'fetchVoiceLibrary()', 'keyPresent = true',
                       'URLQueryItem(name: "page_size", value: "100")',
                       'voiceID = voice.id',
                       'Self.readKey()',
                       'samplePlayer?.play()'):
            self.assertIn(marker, SERVICE)
        self.assertNotIn('enabled = true', SERVICE[SERVICE.index('func selectLibraryVoice'):SERVICE.index('func preview(fallback:')])
        self.assertIn('https://api.elevenlabs.io/v1/voices', SERVICE)
        self.assertIn('if [400, 404, 422].contains(http.statusCode)', SERVICE)
        self.assertIn('Voice ID 저장', LIB)
        self.assertIn('checkVoiceConnection()', LIB)
        self.assertIn('목록 조회가 안 된다면 · Voice ID 직접 연결', LIB)
        self.assertNotIn('xi-api-key', LIB)
        self.assertIn('목록 조회와 선택은 음성 생성 크레딧을 쓰지 않습니다.', LIB)
        self.assertIn('Button("샘플 듣기")', LIB)
    def test_on_demand_window_and_shared_voice_identity(self):
        self.assertIn('Window("ElevenLabs 목소리 선택", id: "jarvis-elevenlabs-voices")', APP)
        self.assertIn('openWindow(id: "jarvis-elevenlabs-voices")', APP)
        self.assertIn('ElevenLabsVoiceService.shared', APP)
        self.assertIn('.defaultLaunchBehavior(.suppressed)', APP)
        self.assertIn('ElevenLabsVoiceService.shared', LIB)

if __name__ == '__main__': unittest.main()
