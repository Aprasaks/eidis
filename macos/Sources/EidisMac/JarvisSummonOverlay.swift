import AppKit
import AVFoundation
import Carbon
import SwiftUI

/// Full-display, dismissible JARVIS presence. It does not change the user's wallpaper
/// or interfere with the underlying desktop once dismissed.
@MainActor
final class JarvisSummonOverlay: ObservableObject {
    static let shared = JarvisSummonOverlay()
    @Published private(set) var visible = false
    private var panel: JarvisOverlayPanel?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func installShortcut() {
        guard hotKey == nil else { return }
        var keyID = EventHotKeyID(signature: OSType(0x4A525653), id: 1) // JRVS
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(cmdKey | shiftKey),
                                         keyID, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var key = EventHotKeyID()
            let code = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            if code == noErr && key.signature == 0x4A525653 && key.id == 1 {
                Task { @MainActor in JarvisSummonOverlay.shared.toggle() }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &eventType, nil, &handler)
    }

    func toggle() { visible ? dismiss() : summon() }

    func summon() {
        guard !visible else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let overlay = JarvisOverlayPanel(contentRect: screen.frame, styleMask: [.borderless],
                                         backing: .buffered, defer: false)
        overlay.level = .screenSaver
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlay.contentView = NSHostingView(rootView: JarvisSummonView(onDismiss: { [weak self] in
            self?.dismiss()
        }))
        panel = overlay
        visible = true
        overlay.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        visible = false
    }
}

final class JarvisOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { JarvisSummonOverlay.shared.dismiss() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { JarvisSummonOverlay.shared.dismiss() }
        else { super.keyDown(with: event) }
    }
}

struct JarvisSummonView: View {
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { size in
            ZStack {
                Color.black.opacity(0.91)
                RadialGradient(colors: [Color(red: 0.38, green: 0.14, blue: 0.01).opacity(0.37),
                                        .clear], center: .center, startRadius: 40,
                               endRadius: min(size.size.width, size.size.height) * 0.53)
                VStack(spacing: 0) {
                    Spacer()
                    JarvisSummonCoreView()
                        .frame(width: min(size.size.width * 0.76, size.size.height * 0.90),
                               height: min(size.size.width * 0.76, size.size.height * 0.90))
                    Text("J A R V I S")
                        .font(.system(size: 16, weight: .ultraLight, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(Color(red: 0.96, green: 0.65, blue: 0.25))
                    Spacer()
                    Text("⌘⇧J  소환 / 닫기     ·     Esc  닫기")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.44))
                        .padding(.bottom, 25)
                }
                VStack {
                    HStack {
                        Spacer()
                        Button("닫기", action: onDismiss)
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(22)
                    }
                    Spacer()
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct JarvisSummonCoreView: View {
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "JARVIS_Overlay_Loop", withExtension: "mp4"),
               !reduceMotion {
                JarvisLoopingMovie(url: url)
            } else {
                JarvisHologramView(animated: !reduceMotion)
            }
        }
        .accessibilityLabel("금빛 자비스 코어")
    }
}

/// AVPlayerLayer avoids transport controls and preserves cinematic loop framing.
struct JarvisLoopingMovie: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> JarvisMovieSurface {
        let surface = JarvisMovieSurface()
        surface.setMovie(url)
        return surface
    }
    func updateNSView(_ view: JarvisMovieSurface, context: Context) {}
}

final class JarvisMovieSurface: NSView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    override var wantsUpdateLayer: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func setMovie(_ url: URL) {
        let queue = AVQueuePlayer()
        queue.isMuted = true
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        if let videoLayer = layer as? AVPlayerLayer {
            videoLayer.player = queue
            videoLayer.videoGravity = .resizeAspect
            videoLayer.backgroundColor = NSColor.clear.cgColor
        }
        queue.play()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { player?.pause() }
    }
}
