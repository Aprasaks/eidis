from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
LIVE=(ROOT/'macos/Sources/EidisMac/JarvisLiveDashboard.swift').read_text()
CONV=(ROOT/'macos/Sources/EidisMac/JarvisOverlayConversation.swift').read_text()
UI=(ROOT/'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
INFO=(ROOT/'macos/Resources/Info.plist').read_text()

class LiveDashboardContract(unittest.TestCase):
    def test_real_readonly_sources_and_polling_only_while_visible(self):
        for marker in ('/api/projects', '/api/vault?limit=12', '/api/diagnostics',
                       '/api/status', '/api/version', '127.0.0.1',
                       'intervalNanoseconds: UInt64 = 7_000_000_000',
                       'while !Task.isCancelled', 'pollingTask?.cancel()',
                       'guard isVisible && revision == id',
                       'URLSessionConfiguration.ephemeral', 'reloadIgnoringLocalCacheData',
                       'projectsReady = false', 'vaultTotal = nil', 'errorText = success ? nil'):
            self.assertIn(marker,LIVE)
        self.assertNotIn('api.openai.com',LIVE)
        self.assertNotIn('https://',LIVE)
        self.assertNotIn('INSERT INTO',LIVE)
        # Only the user's explicit YouTube Connect action sends a POST.
        self.assertIn('request.httpMethod = "POST"', LIVE)
        self.assertIn('/api/youtube/connect', LIVE)
    def test_native_visualization_and_natural_language_routing(self):
        for marker in ('@ObservedObject var liveDashboard: JarvisLiveDashboard',
                       'private var liveDashboardPanel:', 'jarvis-live-dashboard-panel',
                       'liveProjectSection', 'liveKnowledgeSection', 'liveSystemSection',
                       'liveProgress(', 'liveDashboard.refreshedAt',
                       'liveDashboard: dialogue.liveDashboard'):
            self.assertIn(marker,UI)
        for marker in ('let liveDashboard = JarvisLiveDashboard()',
                       'JarvisLiveDashboardIntent.parse(prompt)',
                       'await liveDashboard.show(mode)', 'liveDashboard.hide()',
                       'liveDashboard.cancel()', 'isGenericPanelClose'):
            self.assertIn(marker,CONV)
        self.assertIn('case .unavailable:',CONV)
        self.assertIn('_ = liveDashboard.hide()  // Never leave stale unrelated numbers visible.',CONV)
        self.assertIn('externalSignals = [',LIVE)
        self.assertIn('<string>3.14.3</string>',INFO)
    def test_no_fabricated_status(self):
        self.assertIn('실제 값 확인 필요',UI)
        self.assertIn('연결 안 됨',UI)
        self.assertIn('Qwen 서비스 / Ollama',UI)
        self.assertIn('GPU·메모리 사용량은 측정하지 않았습니다',UI)
        self.assertIn('Only fetch the data sources needed', LIVE)

if __name__=='__main__': unittest.main()
