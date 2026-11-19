from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
INTENT=(ROOT/'macos/Sources/EidisMac/JarvisWebIntent.swift').read_text()
WEB=(ROOT/'macos/Sources/EidisMac/JarvisOverlayBrowser.swift').read_text()
CHAT=(ROOT/'macos/Sources/EidisMac/JarvisOverlayConversation.swift').read_text()
ENGINE=(ROOT/'macos/Sources/EidisMac/JarvisCommandEngine.swift').read_text()
OVERLAY=(ROOT/'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
APP=(ROOT/'macos/Resources/Info.plist').read_text()

class JarvisEmbeddedBrowserContract(unittest.TestCase):
    def test_explicit_web_search_and_private_filename_separation(self):
        for token in ['enum JarvisWebIntent', 'case search(String, engine: SearchEngine)',
                      'm.search.naver.com', 'www.google.com', 'URLQueryItem(name: "query", value: query)',
                      'URLQueryItem(name: "q", value: query)', '"내파일"', '"내프로젝트"',
                      '"찾아줘"', '"검색해줘"', 'case hide', 'String(query.prefix(180))']:
            self.assertIn(token,INTENT)
        self.assertIn('JarvisWebIntent.parse(phrase)',ENGINE)
        self.assertIn('case .searchWeb(let query, let engine)', CHAT)
        self.assertIn('result = browser.search(query, engine: engine)', CHAT)
        self.assertIn('case .browser: result = browser.hide()',CHAT)
        self.assertIn('planAndRespond(prompt, token: token)',CHAT)
        self.assertIn('browser.openHome(engine: engine)',CHAT)
        self.assertIn('browser.cancel()',CHAT)
    def test_real_webview_with_no_page_to_command_bridge(self):
        for token in ['WKWebView', 'WKNavigationDelegate', 'WKUIDelegate',
                      'configuration.websiteDataStore = .nonPersistent()',
                      'url.scheme == "https"', 'scheme == "https" || scheme == "about"',
                      'decisionHandler(.cancel)', 'webView.load(URLRequest(url: url))',
                      'view.stopLoading()', 'view.allowsBackForwardNavigationGestures = true']:
            self.assertIn(token, WEB)
        self.assertNotIn('WKScriptMessageHandler',WEB)
        self.assertNotIn('evaluateJavaScript', WEB)
        self.assertNotIn('Process()',WEB)
        self.assertNotIn('NSWorkspace.shared.open',WEB)
    def test_overlay_only_on_demand_and_esc(self):
        for token in ['if browser.isVisible, let url = browser.currentURL',
                      'JarvisEmbeddedBrowser(browser: browser, url: url)',
                      'jarvis-internal-web-browser', 'jarvis-browser-close',
                      '.frame(width: min(790, max(510, area.size.width * 0.29))',
                      'browser: dialogue.browser', 'hotkey?.uninstallEscape()',
                      'self.dialogue?.browser.isVisible != true', 'JARVIS_FullHD_Loop']:
            self.assertIn(token,OVERLAY)
        self.assertIn('<string>3.10.8</string>',APP)

if __name__ == '__main__': unittest.main()
