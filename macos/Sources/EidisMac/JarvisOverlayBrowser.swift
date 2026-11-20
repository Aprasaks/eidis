import Foundation
import SwiftUI
import WebKit

/// Read-only snapshot of the currently loaded webpage.
/// This text is untrusted evidence, never instructions for JARVIS tools.
struct JarvisWebPageSnapshot {
    let title: String
    let url: URL
    let text: String
}

enum JarvisWebPageReadError: Error {
    case noOpenPage, pageStillLoading, unavailableText, navigationChanged
}

/// User-requested web search is displayed in the overlay, not Safari/Chrome.
/// A fresh ephemeral WKWebView is constructed only when a search is requested.
@MainActor
final class JarvisOverlayBrowser: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var title = "인터넷 검색"
    @Published private(set) var query = ""
    @Published private(set) var currentURL: URL?
    @Published private(set) var pageTitle = ""
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorText: String?
    private weak var webView: WKWebView?

    /// Opening a browser is a separate action from searching the web.
    func openHome(engine: JarvisWebIntent.SearchEngine) -> String {
        let url = engine == .google
            ? URL(string: "https://www.google.com/")!
            : URL(string: "https://m.naver.com/")!
        title = engine == .google ? "Google" : "네이버"
        query = engine == .google ? "구글 홈" : "네이버 홈"
        errorText = nil
        pageTitle = ""
        currentURL = url
        isLoading = true
        isVisible = true
        return "\(title) 브라우저를 DECHIVE 화면 안에 열었습니다."
    }

    func search(_ query: String, engine: JarvisWebIntent.SearchEngine) -> String {
        guard let url = engine.url(for: query) else { return "검색어를 확인해 주세요." }
        title = "\(engine.title) 검색"
        self.query = query
        errorText = nil
        pageTitle = ""
        currentURL = url
        isLoading = true
        isVisible = true
        return "‘\(query)’ 검색 결과를 DECHIVE 화면에 띄웠습니다. 원하시는 링크를 직접 열어볼 수 있습니다."
    }

    /// Read only the currently visible webpage at explicit user request.
    /// No DOM/website content is fed into the tool-selection model call.
    func snapshotVisiblePage() async throws -> JarvisWebPageSnapshot {
        guard isVisible, let view = webView,
              let current = view.url,
              current.scheme?.lowercased() == "https",
              current.host != nil else {
            throw JarvisWebPageReadError.noOpenPage
        }
        guard !view.isLoading else { throw JarvisWebPageReadError.pageStillLoading }
        // Text only: no HTML, scripts, cookies, form values or selected files.
        // Prefer article/main content, falling back to visible body text.
        let js = """
        (() => {
            const body = document.querySelector('article, main, [role="main"]') || document.body;
            if (!body) return '';
            return (body.innerText || '').slice(0, 12000);
        })()
        """
        let raw = try await view.evaluateJavaScript(js)
        guard isVisible, webView === view, view.url == current, !view.isLoading else {
            throw JarvisWebPageReadError.navigationChanged
        }
        guard let text = raw as? String else { throw JarvisWebPageReadError.unavailableText }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.count >= 100 else { throw JarvisWebPageReadError.unavailableText }
        return JarvisWebPageSnapshot(title: String((view.title ?? current.host ?? "웹페이지").prefix(150)),
                                     url: current, text: content)
    }

    func back() { webView?.goBack() }
    func forward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func updateState(_ view: WKWebView) {
        guard isVisible, webView === view else { return }
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
        isLoading = view.isLoading
        pageTitle = view.title ?? ""
    }

    func attach(_ view: WKWebView) {
        webView = view
        updateState(view)
    }

    func failed(_ error: Error) {
        isLoading = false
        errorText = "페이지를 표시하지 못했습니다. 검색어나 네트워크 연결을 확인해 주세요."
    }

    func hide() -> String {
        isVisible = false
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        webView = nil
        currentURL = nil
        pageTitle = ""
        isLoading = false
        canGoBack = false
        canGoForward = false
        errorText = nil
        return "인터넷 검색 창을 닫았습니다."
    }
    func cancel() { _ = hide() }
}

/// Renders a real, interactive browser inside the gold-core overlay.
/// Pages are untrusted content; no JS bridge or access to Qwen, files or commands.
struct JarvisEmbeddedBrowser: NSViewRepresentable {
    @ObservedObject var browser: JarvisOverlayBrowser
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        browser.attach(view)
        context.coordinator.lastRequestedURL = url
        view.load(URLRequest(url: url))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.lastRequestedURL != url else { return }
        context.coordinator.lastRequestedURL = url
        view.load(URLRequest(url: url))
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let browser: JarvisOverlayBrowser
        var lastRequestedURL: URL?
        init(browser: JarvisOverlayBrowser) { self.browser = browser }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "about" else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in browser.updateState(webView) }
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in browser.updateState(webView) }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in browser.failed(error) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Keep target=_blank links inside the existing JARVIS panel.
            if action.targetFrame == nil, let url = action.request.url, url.scheme == "https" {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
