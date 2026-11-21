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

/// A link observed in the currently loaded and visible WebKit document.
struct JarvisObservedLink: Identifiable {
    let number: Int
    let title: String
    let url: URL
    var id: Int { number }
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
    @Published private(set) var isEditingWebText = false
    @Published private(set) var observedLinks: [JarvisObservedLink] = []
    @Published private(set) var lastControlReceipt = ""
    @Published private(set) var navigationCompletionCount = 0
    @Published private(set) var lastObservedURL: URL?
    private var linkSourceURL: URL?
    private weak var webView: WKWebView?

    /// Opening a browser is a separate action from searching the web.
    func openHome(engine: JarvisWebIntent.SearchEngine) -> String {
        let url = engine == .google
            ? URL(string: "https://www.google.com/")!
            : URL(string: "https://m.naver.com/")!
        clearLinkState()
        lastControlReceipt = ""
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
        clearLinkState()
        lastControlReceipt = ""
        title = "\(engine.title) 검색"
        self.query = query
        errorText = nil
        pageTitle = ""
        currentURL = url
        isLoading = true
        isVisible = true
        return "‘\(query)’ 검색 결과를 DECHIVE 화면에 띄웠습니다. 원하시는 링크를 직접 열어볼 수 있습니다."
    }

    // Browser Control 1.0 always acts inside this temporary non-persistent
    // WebKit view; it never touches a real Chrome, Safari or logged-in tab.
    func control(_ action: JarvisBrowserControlIntent) async -> String {
        switch action {
        case .open(let url):
            return await navigate(url, sameHostOnly: false)
        case .links:
            return await listVisibleLinks()
        case .follow(let number):
            guard let view=readyPage(), linkSourceURL == view.url,
                  let link=observedLinks.first(where:{$0.number==number}) else {
                return "주인님, 현재 페이지에서 확인된 링크 목록이 없습니다. 먼저 '링크 목록 보여줘'라고 해주세요."
            }
            guard JarvisBrowserControlPolicy.safeReadOnlyLink(link.url, from:view.url!) else {
                return "주인님, 로그인·결제 등으로 이어지거나 다른 사이트로 이동하는 링크는 자동으로 누르지 않습니다."
            }
            return await navigate(link.url,sameHostOnly:true)
        case .typeSearch(let query):
            return await typeSearchQuery(query)
        case .scrollDown:
            return await scrollPage(1)
        case .scrollUp:
            return await scrollPage(-1)
        case .inspect:
            guard let page=readyPage(), let url=page.url else {
                return "주인님, 실제로 로딩이 끝난 웹페이지가 없습니다."
            }
            let title=String((page.title ?? "제목 확인 불가").prefix(120))
            let answer="주인님, 현재 내부 브라우저에 열린 페이지는 \(title)입니다. 확인된 주소: \(url.absoluteString)"
            lastControlReceipt=answer
            return answer
        }
    }

    private func clearLinkState() {
        observedLinks=[]
        linkSourceURL=nil
    }

    private func readyPage() -> WKWebView? {
        guard isVisible,let page=webView, !page.isLoading,
              let url=page.url, JarvisBrowserControlPolicy.safePublicURL(url),
              errorText==nil else { return nil }
        return page
    }

    private func navigate(_ url:URL,sameHostOnly:Bool) async -> String {
        guard JarvisBrowserControlPolicy.safePublicURL(url) else {
            return "주인님, 자동 탐색은 공개 HTTPS 주소만 허용합니다. 내부 주소와 위험한 URL은 열지 않습니다."
        }
        if sameHostOnly,let existing=webView?.url,
           !JarvisBrowserControlPolicy.safeReadOnlyLink(url,from:existing) {
            return "주인님, 안전한 동일 사이트 링크만 자동 탐색할 수 있습니다."
        }
        let prior=readyPage()?.url
        let previousCompletion=navigationCompletionCount
        let requiresNewLoad=prior?.absoluteString != url.absoluteString
        clearLinkState()
        errorText=nil
        pageTitle=""
        currentURL=url
        isLoading=true
        isVisible=true
        lastControlReceipt="접속 확인 중: \(url.host ?? "주소 미확인")"
        // SwiftUI may mount a WKWebView after the action has started.
        // Report success only after its real navigation reached a loaded page.
        for _ in 0..<76 {
            if Task.isCancelled { return "페이지 확인이 중단되었습니다." }
            guard isVisible, currentURL==url else {
                return "페이지 전환 중 창이 바뀌어 완료를 확인하지 못했습니다."
            }
            if let errorText {
                lastControlReceipt="접속 실패: \(url.host ?? "페이지")"
                return "주인님, 실제 페이지 접속에 실패했습니다. \(errorText)"
            }
            if let view=webView, !view.isLoading,let loaded=view.url,
               loaded.host?.lowercased()==url.host?.lowercased(),
               (!requiresNewLoad || navigationCompletionCount>previousCompletion),
               JarvisBrowserControlPolicy.safePublicURL(loaded),
               !(view.title ?? "").isEmpty {
                let title=String((view.title ?? loaded.host ?? "제목 미확인").prefix(110))
                let redirect = loaded.absoluteString == url.absoluteString ? "" :
                    "요청 주소에서 같은 사이트의 다른 주소로 리디렉션되었습니다. "
                let text="주인님, 실제 웹페이지 로딩을 확인했습니다. " +
                    redirect + "\(title) — 실제 주소: \(loaded.absoluteString)"
                lastControlReceipt=text
                return text
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        lastControlReceipt="요청 주소 \(url.absoluteString) · 실제 확인 주소 \(lastObservedURL?.absoluteString ?? "없음") · 완료 \(navigationCompletionCount)/\(previousCompletion)"
        return "주인님, 웹페이지를 열도록 요청했지만 제한 시간 안에 실제 로딩 완료를 확인하지 못했습니다. 실제 주소: \(lastObservedURL?.absoluteString ?? "미확인")"
    }

    private func listVisibleLinks() async -> String {
        guard let view=readyPage(),let url=view.url else {
            return "주인님, 먼저 페이지를 열고 로딩이 끝난 뒤 링크를 확인해 주세요."
        }
        // DOM values are untrusted and are never executed as tool instructions.
        let js = """
        (() => Array.from(document.querySelectorAll('a[href]')).filter(a => {
            const box = a.getBoundingClientRect();
            const style = window.getComputedStyle(a);
            return box.width > 0 && box.height > 0 && box.bottom > 0 &&
                   box.top < window.innerHeight && style.visibility !== 'hidden' &&
                   style.display !== 'none';
        }).map(a => ({
            title: String(a.innerText || a.getAttribute('aria-label') || a.title || '').trim().slice(0, 140),
            href: a.href
        })).filter(a => a.title.length > 2).slice(0, 90))()
        """
        do {
            let value=try await view.evaluateJavaScript(js)
            guard !Task.isCancelled,readyPage() === view,view.url==url,
                  let raw=value as? [[String: Any]] else {
                return "주인님, 웹페이지가 변경되어 링크 목록을 확정할 수 없습니다."
            }
            var links:[JarvisObservedLink]=[]
            var seen=Set<String>()
            for item in raw {
                guard links.count<12,
                      let title=item["title"] as? String,let target=item["href"] as? String,
                      let link=URL(string:target),
                      !title.isEmpty,
                      JarvisBrowserControlPolicy.safeReadOnlyLink(link,from:url),
                      !seen.contains(link.absoluteString) else { continue }
                seen.insert(link.absoluteString)
                links.append(.init(number:links.count+1,title:String(title.prefix(85)),url:link))
            }
            observedLinks=links
            linkSourceURL=url
            guard !links.isEmpty else {
                lastControlReceipt="현재 화면에서 안전한 동일 도메인 링크를 찾지 못함"
                return "주인님, 현재 보이는 화면에 자동으로 열 수 있는 안전한 동일 사이트 링크가 없습니다. 스크롤해 다시 확인할 수 있습니다."
            }
            lastControlReceipt="실제 화면의 안전한 링크 \(links.count)개 확인"
            let list=links.prefix(8).map {
                "링크 \($0.number)번: \($0.title)"
            }
            return "주인님, 현재 웹페이지에서 확인된 링크입니다.\n" + list.joined(separator:"\n") +
                (links.count>8 ? "\n나머지 \(links.count-8)개도 목록에 남겼습니다." : "") +
                "\n원하는 링크 번호를 말씀해 주세요. 같은 사이트의 읽기 전용 링크만 열 수 있습니다."
        } catch {
            return "주인님, 웹페이지에서 링크를 읽지 못했습니다. 실제 링크를 확인하지 않은 상태입니다."
        }
    }

    private func typeSearchQuery(_ input:String) async -> String {
        guard let view=readyPage(),let url=view.url else {
            return "주인님, 먼저 웹페이지를 연 뒤 검색창에 입력해 주세요."
        }
        // Only searchbox, never password/email/payment/general text fields.
        // callAsyncJavaScript binds input as an argument, not executable JS.
        let js = """
        const items = Array.from(document.querySelectorAll(
            'input[type="search"],input[role="searchbox"]'));
        const field = items.find(el => {
            const b=el.getBoundingClientRect();
            return b.width>0 && b.height>0 && b.bottom>0 &&
                   b.top<window.innerHeight && !el.disabled && !el.readOnly &&
                   (el.type==='search' || el.getAttribute('role')==='searchbox');
        });
        if (!field || !('value' in field) || field.type==='password') {
            return {ok:false,reason:'no_visible_searchbox'};
        }
        const setter = Object.getOwnPropertyDescriptor(
            window.HTMLInputElement.prototype, 'value')?.set;
        if (!setter) return {ok:false,reason:'unsupported_input'};
        setter.call(field, String(requestedValue).slice(0,120));
        field.dispatchEvent(new Event('input',{bubbles:true}));
        return {ok:field.value===requestedValue,reason:'input_only'};
        """
        do {
            let response=try await view.callAsyncJavaScript(
                js,arguments:["requestedValue":input],in:nil,contentWorld:.page)
            guard !Task.isCancelled,readyPage() === view,view.url==url,
                  let result=response as? [String:Any],
                  result["ok"] as? Bool == true else {
                return "주인님, 화면의 검색창에 입력됐는지 확인하지 못했습니다. 직접 확인해 주세요."
            }
            let message="주인님, 현재 페이지의 검색 전용 입력창에 문구를 입력한 것을 확인했습니다. 제출 버튼이나 Enter는 누르지 않았습니다."
            lastControlReceipt=message
            return message
        } catch {
            return "주인님, 검색창 입력을 완료했다고 확인할 수 없습니다."
        }
    }

    private func scrollPage(_ direction:Int) async -> String {
        guard let view=readyPage(),let url=view.url else {
            return "주인님, 로딩이 끝난 페이지가 없어서 스크롤하지 않았습니다."
        }
        do {
            let response=try await view.evaluateJavaScript("""
                (() => {
                    const before = window.scrollY;
                    window.scrollBy(0, \(direction > 0 ? 550 : -550));
                    return {before,after:window.scrollY};
                })()
                """)
            guard !Task.isCancelled,readyPage() === view,view.url==url,
                  let item=response as? [String:Any],
                  let before=item["before"] as? Double,
                  let after=item["after"] as? Double else {
                return "주인님, 스크롤 결과를 검증하지 못했습니다."
            }
            guard abs(after-before)>1 else {
                return "주인님, 이 페이지는 해당 방향으로 더 스크롤되지 않았습니다."
            }
            clearLinkState() // old visible links are no longer a valid selection.
            let label=direction>0 ? "아래" : "위"
            lastControlReceipt="스크롤 \(label) · 실제 이동 확인"
            return "주인님, 실제 페이지를 \(label)로 스크롤한 것을 확인했습니다. 링크 목록은 새 화면 기준으로 다시 읽어야 합니다."
        } catch {
            return "주인님, 스크롤에 성공했는지 확인하지 못했습니다."
        }
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

    func back() { clearLinkState(); lastControlReceipt = ""; webView?.goBack() }
    func forward() { clearLinkState(); lastControlReceipt = ""; webView?.goForward() }
    func reload() { clearLinkState(); lastControlReceipt = ""; webView?.reload() }

    func updateState(_ view: WKWebView) {
        guard isVisible, webView === view else { return }
        if linkSourceURL != nil && linkSourceURL != view.url {
            clearLinkState()
        }
        lastObservedURL = view.url
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
        isLoading = view.isLoading
        pageTitle = view.title ?? ""
    }

    func attach(_ view: WKWebView) {
        webView = view
        isEditingWebText = false
        updateState(view)
    }

    func updateWebTextEditing(_ editing: Bool, in view: WKWebView?) {
        guard isVisible, webView === view else { return }
        isEditingWebText = editing
    }

    func rejectHTTPPage(_ statusCode: Int) {
        clearLinkState()
        isLoading = false
        errorText = "HTTP \(statusCode) 응답으로 페이지 조회가 확인되지 않았습니다."
    }

    func failed(_ error: Error) {
        clearLinkState()
        isLoading = false
        errorText = "페이지를 표시하지 못했습니다. 검색어나 네트워크 연결을 확인해 주세요."
    }

    func navigationFinished(_ view: WKWebView) {
        guard isVisible, webView === view else { return }
        navigationCompletionCount += 1
        updateState(view)
    }

    func hide() -> String {
        isVisible = false
        isEditingWebText = false
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        webView = nil
        currentURL = nil
        pageTitle = ""
        isLoading = false
        canGoBack = false
        canGoForward = false
        errorText = nil
        clearLinkState()
        lastControlReceipt = ""
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
        // The bridge reports only whether an editable input owns focus.
        // It does not read keystrokes, text, cookies, or page contents.
        let webInputFocusScript = """
        (() => {
            if (window.__dechiveFocusInstalled) return;
            window.__dechiveFocusInstalled = true;
            const notify = () => {
                let active = document.activeElement;
                while (active && active.shadowRoot && active.shadowRoot.activeElement) {
                    active = active.shadowRoot.activeElement;
                }
                const editing = !!active && (
                    active.matches?.('input, textarea, select, [role="textbox"], [role="searchbox"]') ||
                    active.isContentEditable === true
                );
                window.webkit.messageHandlers.dechiveInputFocus.postMessage(Boolean(editing));
            };
            document.addEventListener('focusin', notify, true);
            document.addEventListener('focusout', () => setTimeout(notify, 0), true);
            window.addEventListener('blur', notify);
            notify();
        })();
        """
        configuration.userContentController.add(context.coordinator,
            name: "dechiveInputFocus")
        configuration.userContentController.addUserScript(
            WKUserScript(source: webInputFocusScript, injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true))
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
        view.configuration.userContentController.removeScriptMessageHandler(
            forName: "dechiveInputFocus")
        view.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate,
                              WKScriptMessageHandler {
        let browser: JarvisOverlayBrowser
        var lastRequestedURL: URL?
        init(browser: JarvisOverlayBrowser) { self.browser = browser }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "dechiveInputFocus",
                  message.frameInfo.isMainFrame,
                  let focused = message.body as? Bool else { return }
            let view = message.webView
            Task { @MainActor in
                browser.updateWebTextEditing(focused, in: view)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url,
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "https" && JarvisBrowserControlPolicy.safePublicURL(url)) ||
                  (scheme == "about" && url.absoluteString == "about:blank") else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse,
               http.statusCode >= 400 {
                Task { @MainActor in browser.rejectHTTPPage(http.statusCode) }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in browser.navigationFinished(webView) }
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                browser.updateWebTextEditing(false, in: webView)
                browser.updateState(webView)
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in browser.failed(error) }
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
