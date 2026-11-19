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
    let moveToAdjacentScreen: (Int) -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { area in
            ZStack {
                // Full-HD original has a black backdrop. Match it without
                // chroma-key artifacts or a visibly scaled transparency matte.
                Color.black.opacity(appeared ? 1 : 0)
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
            // Drag the hologram left/right to move it between physical screens.
            // This never changes the user's macOS Spaces or rearranges windows.
            .simultaneousGesture(
                DragGesture(minimumDistance: 80)
                    .onEnded { value in
                        if abs(value.translation.width) > 100 &&
                           abs(value.translation.width) > abs(value.translation.height) * 1.25 {
                            moveToAdjacentScreen(value.translation.width < 0 ? 1 : -1)
                        }
                    }
            )
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
    private var interactionMonitor: Any?
    private var lastScrollInput = Date.distantPast
    private var horizontalScrollTotal: CGFloat = 0
    private var lastMove = Date.distantPast
    private var lastToggle = Date.distantPast
    private var hiddenAppWindows: [NSWindow] = []
    private let greetingFallback = JarvisVoiceService()
    private var greetingTask: Task<Void, Never>?

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
              let url = Bundle.main.url(forResource: "JARVIS_FullHD_Loop", withExtension: "mp4")
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
            videoURL: url,
            dismiss: { [weak self] in self?.dismiss() },
            moveToAdjacentScreen: { [weak self] direction in self?.moveToAdjacentScreen(direction) }))
        // Do not show the old JARVIS dashboard behind the cinematic veil.
        // orderOut keeps its state and project data intact; the Dock can reopen it.
        hiddenAppWindows = NSApp.windows.filter { $0 !== window && $0.isVisible }
        for oldWindow in hiddenAppWindows { oldWindow.orderOut(nil) }
        panel = window
        NSLog("JARVIS: panel created, frame=%@", NSStringFromRect(window.frame))
        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            if event.type == .keyDown {
                // Escape must win over animation, dialogue and other overlay states.
                if event.keyCode == 53 {
                    self.dismiss()
                    return nil
                }
                // Reliable fallback when trackpad gestures are unavailable.
                if event.keyCode == 123 || event.keyCode == 124 {
                    self.moveToAdjacentScreen(event.keyCode == 123 ? -1 : 1)
                    return nil
                }
            } else if event.type == .scrollWheel {
                self.handleHorizontalScroll(event)
            }
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
        // Speak only after the core is onscreen. This reuses the already
        // consented ElevenLabs service; no wake-word/microphone runs here.
        greetingTask?.cancel()
        greetingTask = Task { [weak self] in
            guard let self, self.panel != nil else { return }
            await ElevenLabsVoiceService.shared.speakSummonGreeting(fallback: self.greetingFallback)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSLog("JARVIS: overlay stable, isVisible=%@ alpha=%.2f appHidden=%@",
                  window.isVisible.description, window.alphaValue, NSApp.isHidden.description)
        }
    }

    /// Two-finger horizontal trackpad swipe. Ignore vertical or small scrolls.
    private func handleHorizontalScroll(_ event: NSEvent) {
        let horizontal = CGFloat(event.scrollingDeltaX)
        let vertical = CGFloat(event.scrollingDeltaY)
        guard abs(horizontal) > 0.7, abs(horizontal) > abs(vertical) * 1.15 else { return }
        if Date().timeIntervalSince(lastScrollInput) > 0.4 { horizontalScrollTotal = 0 }
        lastScrollInput = Date()
        horizontalScrollTotal += horizontal
        guard abs(horizontalScrollTotal) > 80 else { return }
        let direction = horizontalScrollTotal > 0 ? -1 : 1
        horizontalScrollTotal = 0
        moveToAdjacentScreen(direction)
    }

    /// Move the *same* playing panel between physical displays, preserving the core.
    func moveToAdjacentScreen(_ direction: Int) {
        guard let panel, direction != 0,
              Date().timeIntervalSince(lastMove) > 0.65 else { return }
        let screens = NSScreen.screens.sorted {
            if abs($0.frame.midX - $1.frame.midX) > 1 { return $0.frame.midX < $1.frame.midX }
            return $0.frame.midY < $1.frame.midY
        }
        guard screens.count > 1 else { return }
        let middle = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let current = screens.firstIndex(where: { $0.frame.contains(middle) }) ??
            screens.enumerated().min(by: {
                abs($0.element.frame.midX - middle.x) < abs($1.element.frame.midX - middle.x)
            })?.offset ?? 0
        let next = current + (direction > 0 ? 1 : -1)
        guard screens.indices.contains(next) else { return }
        lastMove = Date()
        panel.setFrame(screens[next].frame, display: true, animate: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        NSLog("JARVIS: moved core display %ld -> %ld", current, next)
    }

    /// Immediate dismissal: do not wait for a fade when the user presses Esc.
    func dismiss() {
        guard let window = panel else { return }
        // Highest priority: stop audio and cancel outstanding greeting requests.
        greetingTask?.cancel()
        greetingTask = nil
        ElevenLabsVoiceService.shared.stopSpeakingNow()
        greetingFallback.stop()
        panel = nil
        hiddenAppWindows.removeAll()
        if let interactionMonitor { NSEvent.removeMonitor(interactionMonitor) }
        interactionMonitor = nil
        horizontalScrollTotal = 0
        window.orderOut(nil)
        window.contentView = nil // releases video layer and pauses AVPlayerLooper
    }

    func stop() {
        greetingTask?.cancel()
        greetingTask = nil
        ElevenLabsVoiceService.shared.stopSpeakingNow()
        greetingFallback.stop()
        hotkey?.uninstall()
        hotkey = nil
        if let interactionMonitor { NSEvent.removeMonitor(interactionMonitor) }
        interactionMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        hiddenAppWindows.removeAll()
    }
}
