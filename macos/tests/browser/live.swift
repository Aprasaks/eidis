import AppKit
import SwiftUI
import WebKit
import Foundation

struct BrowserTestSurface: View {
    @ObservedObject var browser: JarvisOverlayBrowser
    var body: some View {
        Group {
            if browser.isVisible, let url=browser.currentURL {
                JarvisEmbeddedBrowser(browser:browser,url:url)
            } else {
                Color.clear
            }
        }
        .frame(width:800,height:650)
    }
}

@main struct BrowserRealWebKit {
    @MainActor static func main() {
        let application=NSApplication.shared
        application.setActivationPolicy(.accessory)
        let browser=JarvisOverlayBrowser()
        let window=NSWindow(contentRect:NSRect(x:-2000,y:-2000,width:800,height:650),
                            styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=NSHostingView(rootView:BrowserTestSurface(browser:browser))
        window.orderFrontRegardless()
        Task { @MainActor in
            let open=await browser.control(.open(URL(string:"https://www.python.org/")!))
            print("OPEN:",open)
            guard open.contains("로딩을 확인했습니다") else {exit(11)}
            let inspect=await browser.control(.inspect)
            print("INSPECT:",inspect)
            guard inspect.contains("python.org") else {exit(12)}
            let list=await browser.control(.links)
            print("VISIBLE_LINK_COUNT:",browser.observedLinks.count,"DETAILS:",String(list.prefix(700)))
            guard !browser.observedLinks.isEmpty else {exit(13)}
            let input=await browser.control(.typeSearch("Python package documentation"))
            print("INPUT:",input)
            guard input.contains("입력한 것을 확인했습니다") else {exit(14)}
            let scroll=await browser.control(.scrollDown)
            print("SCROLL:",scroll)
            guard scroll.contains("실제 페이지를 아래로 스크롤") else {exit(15)}
            let afterScroll=await browser.control(.follow(1))
            print("OLD_LINK_INVALIDATED:",afterScroll)
            guard afterScroll.contains("링크 목록이 없습니다") else {exit(16)}
            _=await browser.control(.scrollUp)
            let again=await browser.control(.links)
            print("NEW_LINKS:",browser.observedLinks.count, "DETAIL:",String(again.prefix(400)))
            guard let chosen=browser.observedLinks.first(where:{
                $0.url.path != "/" && $0.url.absoluteString != "https://www.python.org/"
            }) else {exit(17)}
            let followed=await browser.control(.follow(chosen.number))
            print("FOLLOW:",followed,"ACTUAL:",browser.lastObservedURL?.absoluteString ?? "nil",
                  "COMPLETIONS:",browser.navigationCompletionCount,"LOADING:",browser.isLoading,
                  "ERROR:",browser.errorText ?? "none")
            guard followed.contains("로딩을 확인했습니다"),
                  browser.currentURL == chosen.url,
                  browser.lastObservedURL?.host == chosen.url.host,
                  browser.lastObservedURL != URL(string:"https://www.python.org/")! else {exit(18)}
            print("PASS: real isolated WKWebView page load, title/URL, visible link capture, search text, scroll, stale-link denial and navigation")
            _=browser.hide()
            window.orderOut(nil)
            exit(0)
        }
        application.run()
    }
}
