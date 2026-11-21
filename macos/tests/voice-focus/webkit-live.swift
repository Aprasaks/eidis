import AppKit
import SwiftUI
import WebKit
import Foundation

struct InputFocusFixture: View {
    @ObservedObject var browser: JarvisOverlayBrowser
    var body: some View {
        Group {
            if browser.isVisible,let url=browser.currentURL {
                JarvisEmbeddedBrowser(browser:browser,url:url)
            } else { Color.clear }
        }
        .frame(width:900,height:650)
    }
}

@main struct WebKitFocusSmoke {
    @MainActor static func main() {
        let app=NSApplication.shared
        app.setActivationPolicy(.accessory)
        let browser=JarvisOverlayBrowser()
        let window=NSWindow(contentRect:NSRect(x:-2000,y:-2000,width:900,height:650),
                            styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=NSHostingView(rootView:InputFocusFixture(browser:browser))
        window.orderFrontRegardless()
        func lookup(_ root:NSView?) -> WKWebView? {
            guard let root else {return nil}
            if let web=root as? WKWebView {return web}
            for child in root.subviews {
                if let found=lookup(child) {return found}
            }
            return nil
        }
        Task { @MainActor in
            let result=await browser.control(.open(URL(string:"https://www.python.org/")!))
            print("OPEN:",result)
            guard result.contains("로딩을 확인했습니다") else {exit(21)}
            guard let web=lookup(window.contentView) else {
                print("FAIL: WKWebView not mounted")
                exit(22)
            }
            do {
                let focused=try await web.evaluateJavaScript("""
                    (() => {
                        const field=document.querySelector('input[type="search"]');
                        if (!field) return false;
                        field.focus();
                        return document.activeElement===field;
                    })()
                """)
                print("DOM_FOCUSED:",focused)
                try await Task.sleep(for:.milliseconds(550))
                print("BROWSER_EDITOR_FOCUSED:",browser.isEditingWebText)
                guard browser.isEditingWebText else {exit(23)}
                let typedSpace=JarvisVoiceShortcutPolicy.handles(
                    keyCode:49, modifiers:[],composerEditing:false,browserEditing:browser.isEditingWebText)
                guard !typedSpace else {exit(24)}
                let _=try await web.evaluateJavaScript("document.activeElement.blur(); true")
                try await Task.sleep(for:.milliseconds(550))
                print("BROWSER_EDITOR_BLURRED:",!browser.isEditingWebText)
                guard !browser.isEditingWebText else {exit(25)}
                let bareSpace=JarvisVoiceShortcutPolicy.handles(
                    keyCode:49,modifiers:[],composerEditing:false,browserEditing:browser.isEditingWebText)
                guard bareSpace else {exit(26)}
                print("PASS: real WebKit focus changes preserve normal typing while bare Space voice works outside inputs")
                _=browser.hide()
                window.orderOut(nil)
                exit(0)
            } catch {
                print("ERROR:",error)
                exit(27)
            }
        }
        app.run()
    }
}
