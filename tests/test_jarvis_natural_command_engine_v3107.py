from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
REGISTRY=(ROOT/'macos/Sources/EidisMac/JarvisCommandEngine.swift').read_text()
CHAT=(ROOT/'macos/Sources/EidisMac/JarvisOverlayConversation.swift').read_text()
BROWSER=(ROOT/'macos/Sources/EidisMac/JarvisOverlayBrowser.swift').read_text()

class NaturalCommandEngine(unittest.TestCase):
    def test_qwen_local_structured_tool_calls_and_registry(self):
        for marker in ('"tools": JarvisCommand.tools', '"think": false',
                       '"stream": false', '"model": JarvisLocalModelConfiguration.selectedModel',
                       'JarvisCommand.actions(from: message, utterance: prompt)',
                       'JarvisCommand.directFallback(for: prompt)',
                       'private func execute(_ actions: [JarvisCommand]',
                       'conversation.append(["role": "assistant", "content": output])'):
            self.assertIn(marker,CHAT)
        for name in ('open_browser', 'search_web', 'show_work_dashboard', 'close_panel'):
            self.assertIn('"'+name+'"',REGISTRY)
        self.assertIn('guard calls.count <= 3',REGISTRY)
        self.assertIn('toolNames.contains(name)',REGISTRY)
        self.assertIn('case .openBrowser(let engine):',CHAT)
        self.assertIn('result = browser.openHome(engine: engine)',CHAT)
        self.assertIn('case .showDashboard:',CHAT)
        self.assertIn('result = await dashboard.show()',CHAT)
        self.assertIn('case .closePanel(let panel):',CHAT)
        self.assertIn('private func planAndRespond(',CHAT)
    def test_no_arbitrary_execution_or_private_data_exfiltration(self):
        for item in ('"내파일"', '"내사진"', '"내노션"', '"내옵시디언"',
                     '"/users/"', 'query.contains("@")', 'isSafePublicSearch(',
                     'guard !trimmed.isEmpty && trimmed.count <= 180'):
            self.assertIn(item, REGISTRY)
        for banned in ('Process()', 'NSAppleScript', 'NSWorkspace.shared.open',
                       'eval(', 'api.anthropic.com', 'api.openai.com'):
            self.assertNotIn(banned, REGISTRY+CHAT)
        self.assertIn('guard !Task.isCancelled, token == generation', CHAT)
        self.assertIn('session.invalidateAndCancel()', CHAT)
        self.assertIn('notYetConnectedResponse(for:', CHAT)
        self.assertIn('contextualPanelFallback(for: prompt)', CHAT)
        self.assertIn('현재 이디스 화면:', CHAT)
        self.assertIn('if dashboard.isVisible && !browser.isVisible', CHAT)
        self.assertIn('if browser.isVisible && !dashboard.isVisible', CHAT)
    def test_browser_home_stays_inside_fullscreen(self):
        self.assertIn('func openHome(engine:',BROWSER)
        self.assertIn('https://www.google.com/',BROWSER)
        self.assertIn('https://m.naver.com/',BROWSER)
        self.assertIn('isVisible = true',BROWSER)
        self.assertIn('browser.cancel()',CHAT)

if __name__ == '__main__': unittest.main()
