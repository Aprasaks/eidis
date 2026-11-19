import AppKit
import AVFoundation
import Carbon
import SwiftUI

// Keyboard invocation is always explicit. This preview does not run a microphone
// or claim the '자비스' wake word works.
private final class JarvisOverlayHotkey {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    func install() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let key = Unmanaged<JarvisOverlayHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { key.onPress?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return false }
        let identifier = EventHotKeyID(signature: 0x4A415256, id: 51) // JARV
        let registration = RegisterEventHotKey(UInt32(kVK_ANSI_J),
            UInt32(cmdKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotkey)
        if registration != noErr { uninstall(); return false }
        return true
    }

    func uninstall() {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
        hotkey = nil
        handler = nil
    }
    deinit { uninstall() }
}

private final class JarvisOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class JarvisVideoSurface: NSView {
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
}

private struct JarvisLoopingCore: NSViewRepresentable {
    let videoURL: URL
    final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        init(url: URL) {
            player.isMuted = true
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        }
        deinit { player.pause() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(url: videoURL) }
    func makeNSView(context: Context) -> JarvisVideoSurface {
        let view = JarvisVideoSurface(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.playerLayer?.backgroundColor = NSColor.clear.cgColor
        view.playerLayer?.isOpaque = false
        view.playerLayer?.videoGravity = .resizeAspect
        view.playerLayer?.player = context.coordinator.player
        context.coordinator.player.play()
        return view
    }
    func updateNSView(_ view: JarvisVideoSurface, context: Context) {
        view.playerLayer?.frame = view.bounds
    }
    static func dismantleNSView(_ view: JarvisVideoSurface, coordinator: Coordinator) {
        coordinator.player.pause()
        view.playerLayer?.player = nil
    }
}

private struct JarvisSummonedView: View {
    let videoURL: URL
    let dismiss: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { area in
            ZStack {
                // Keep the user's actual desktop visible, but strongly dimmed.
                Color.black.opacity(appeared ? 0.91 : 0)
                    .ignoresSafeArea()
                JarvisLoopingCore(videoURL: videoURL)
                    .frame(width: area.size.width, height: area.size.height)
                    .opacity(appeared ? 1 : 0)
                    .allowsHitTesting(false)
                VStack {
                    HStack {
                        Spacer()
                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.36))
                                .padding(16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("자비스 화면 닫기")
                    }
                    Spacer()
                    // The supplied activation film already contains the core artwork.
                    // No duplicate HUD text or visible menu is added on top of it.
                }
                .padding(.horizontal, 30)
            }
            .frame(width: area.size.width, height: area.size.height)
        }
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.easeInOut(duration: 0.36)) { appeared = true } }
        }
    }
}

@MainActor
final class JarvisFullscreenOverlay {
    private var hotkey: JarvisOverlayHotkey?
    private var panel: JarvisOverlayPanel?
    private var escapeMonitor: Any?
    private var lastToggle = Date.distantPast
    private var hiddenAppWindows: [NSWindow] = []

    func start() {
        NSLog("JARVIS: overlay start, args=%@", ProcessInfo.processInfo.arguments.joined(separator: ","))
        let key = JarvisOverlayHotkey()
        key.onPress = { [weak self] in self?.toggle() }
        if key.install() {
            hotkey = key
            NSLog("JARVIS: Command-Option-J fullscreen shortcut registered")
        } else {
            NSLog("JARVIS: Command-Option-J shortcut unavailable; overlay not activated")
        }
        // Manual invocation used only for test builds; production launch remains quiet.
        if ProcessInfo.processInfo.arguments.contains("--overlay-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [self] in
                NSLog("JARVIS: demo timer fired")
                self.show()
            }
        }
    }

    func toggle() {
        guard Date().timeIntervalSince(lastToggle) > 0.45 else { return }
        lastToggle = Date()
        if panel == nil { show() } else { dismiss() }
    }

    func show() {
        NSLog("JARVIS: show requested")
        guard panel == nil,
              let screen = NSScreen.main ?? NSScreen.screens.first,
              let url = Bundle.main.url(forResource: "JARVIS_Activation_Alpha_HEVC", withExtension: "mov")
        else {
            NSLog("JARVIS: fullscreen video asset or active screen missing")
            return
        }
        let window = JarvisOverlayPanel(contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // NSPanel hides on app deactivation by default; this overlay must
        // remain onscreen even when Chrome/Finder is the frontmost application.
        window.hidesOnDeactivate = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovable = false
        window.setFrame(screen.frame, display: true)
        window.contentView = NSHostingView(rootView: JarvisSummonedView(
            videoURL: url, dismiss: { [weak self] in self?.dismiss() }))
        // Do not show the old JARVIS dashboard behind the cinematic veil.
        // orderOut keeps its state and project data intact; the Dock can reopen it.
        hiddenAppWindows = NSApp.windows.filter { $0 !== window && $0.isVisible }
        for oldWindow in hiddenAppWindows { oldWindow.orderOut(nil) }
        panel = window
        NSLog("JARVIS: panel created, frame=%@", NSStringFromRect(window.frame))
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil } // Escape
            return event
        }
        // A restored hidden SwiftUI scene can prevent ordinary orderFront from
        // raising a new panel. Explicitly unhide the app and raise the panel.
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Keep window opacity at 1; animate SwiftUI contents instead. Fading the
        // window itself can leave a background NSPanel offscreen on macOS.
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKey()
        NSLog("JARVIS: overlay ordered front, isVisible=%@ alpha=%.2f appHidden=%@",
              window.isVisible.description, window.alphaValue, NSApp.isHidden.description)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSLog("JARVIS: overlay stable, isVisible=%@ alpha=%.2f appHidden=%@",
                  window.isVisible.description, window.alphaValue, NSApp.isHidden.description)
        }
    }

    func dismiss() {
        guard let window = panel else { return }
        panel = nil
        hiddenAppWindows.removeAll()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        NSAnimationContext.runAnimationGroup({ animation in
            animation.duration = 0.28
            window.animator().alphaValue = 0
        }, completionHandler: { window.orderOut(nil); window.contentView = nil })
    }

    func stop() {
        hotkey?.uninstall()
        hotkey = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        hiddenAppWindows.removeAll()
    }
}
