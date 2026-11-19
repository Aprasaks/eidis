import AppKit
import AVFoundation
import Carbon
import SwiftUI

// Keyboard invocation is always explicit. This preview does not run a microphone
// or claim the '자비스' wake word works.
private final class JarvisOverlayHotkey {
    private var hotkey: EventHotKeyRef?
    private var escapeHotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    var onEscape: (() -> Void)?

    func install() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let key = Unmanaged<JarvisOverlayHotkey>.fromOpaque(userData).takeUnretainedValue()
            var pressed = EventHotKeyID()
            let outcome = GetEventParameter(event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard outcome == noErr, pressed.signature == 0x4A415256 else {
                return OSStatus(eventNotHandledErr)
            }
            let hotkeyID = pressed.id
            DispatchQueue.main.async {
                switch hotkeyID {
                case 51: key.onPress?()
                case 52: key.onEscape?()
                default: break
                }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return false }
        let identifier = EventHotKeyID(signature: 0x4A415256, id: 51) // JARV
        let registration = RegisterEventHotKey(UInt32(kVK_ANSI_J),
            UInt32(cmdKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotkey)
        if registration != noErr { uninstall(); return false }
        return true
    }

    /// Register Escape only while fullscreen JARVIS is visible. Unlike a local
    /// key monitor, Carbon receives Escape even if microphone permission UI
    /// or another app temporarily takes keyboard focus.
    func installEscape() -> Bool {
        guard escapeHotkey == nil else { return true }
        let identifier = EventHotKeyID(signature: 0x4A415256, id: 52)
        return RegisterEventHotKey(UInt32(kVK_Escape), 0, identifier,
            GetApplicationEventTarget(), 0, &escapeHotkey) == noErr
    }

    func uninstallEscape() {
        if let escapeHotkey { UnregisterEventHotKey(escapeHotkey) }
        escapeHotkey = nil
    }

    func uninstall() {
        uninstallEscape()
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
    @ObservedObject var dialogue: JarvisOverlayConversation
    @ObservedObject var dashboard: JarvisOverlayDashboard
    @ObservedObject var browser: JarvisOverlayBrowser
    @State private var typedText = ""
    @FocusState private var isInputFocused: Bool
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
                    // The original film and its core remain untouched. Dialogue
                    // controls are compact and confined to the bottom edge.
                    VStack(spacing: 8) {
                        Text(dialogue.status)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(dialogue.isListening ? Color(red: 1, green: 0.72, blue: 0.28) : .white.opacity(0.8))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 9) {
                            Button {
                                dialogue.toggleMicrophone()
                            } label: {
                                Label(dialogue.isListening ? "질문 마치기" : "대화 시작", systemImage: dialogue.isListening ? "stop.circle.fill" : "mic.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.68, green: 0.37, blue: 0.06))
                            .disabled(dialogue.isThinking || dialogue.isSpeaking)
                            .accessibilityIdentifier("jarvis-overlay-microphone")
                            TextField("텍스트로도 질문할 수 있어요", text: $typedText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .focused($isInputFocused)
                                .onChange(of: isInputFocused) { _, focused in
                                    dialogue.textInputFocused = focused
                                }
                                .onSubmit { sendTyped() }
                                .disabled(dialogue.isThinking || dialogue.isSpeaking || dialogue.isListening)
                                .accessibilityIdentifier("jarvis-overlay-text-input")
                            Button("보내기") { sendTyped() }
                                .buttonStyle(.bordered)
                                .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                          dialogue.isThinking || dialogue.isSpeaking || dialogue.isListening)
                                .accessibilityIdentifier("jarvis-overlay-send")
                        }
                    }
                    .frame(maxWidth: 620)
                    .padding(12)
                    .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.bottom, 15)
                }
                .padding(.horizontal, 30)

                // Keep the original JARVIS title unobstructed even for long
                // answers: subtitles sit on the left, not atop the gold core.
                if !dialogue.answer.isEmpty {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(dialogue.question)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.orange.opacity(0.85))
                            Text(dialogue.answer)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.93))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(6)
                        }
                        .frame(width: min(440, area.size.width * 0.34), alignment: .leading)
                        .padding(13)
                        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13)
                            .stroke(.white.opacity(0.12), lineWidth: 1))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 30)
                    .padding(.bottom, 89)
                    .allowsHitTesting(false)
                }

                // Dashboard is summoned on an explicit command only; the gold
                // core artwork/video remains unchanged and visible beneath it.
                if browser.isVisible, let url = browser.currentURL {
                    HStack {
                        Spacer(minLength: 0)
                        embeddedBrowserPanel(url: url)
                            .frame(width: min(790, max(510, area.size.width * 0.29)),
                                   height: min(900, max(540, area.size.height - 95)))
                            .padding(.trailing, 23)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else if dashboard.isVisible {
                    HStack {
                        Spacer(minLength: 0)
                        dashboardPanel
                            .frame(width: min(405, max(295, area.size.width * 0.29)),
                                   height: min(800, max(350, area.size.height - 130)))
                            .padding(.trailing, 27)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(width: area.size.width, height: area.size.height)
            // Drag the hologram left/right to move it between physical screens.
            // This never changes the user's macOS Spaces or rearranges windows.
            .simultaneousGesture(
                DragGesture(minimumDistance: 80)
                    .onEnded { value in
                        // Browsing gestures inside the right-side panel must
                        // navigate that page, not move JARVIS to another monitor.
                        if browser.isVisible && value.startLocation.x > area.size.width * 0.54 { return }
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

    private func embeddedBrowserPanel(url: URL) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "globe")
                    .foregroundStyle(Color.orange)
                Text(browser.title.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white)
                Spacer()
                Button { browser.back() } label: { Image(systemName: "chevron.left") }
                    .disabled(!browser.canGoBack)
                    .accessibilityIdentifier("jarvis-browser-back")
                Button { browser.forward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!browser.canGoForward)
                Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityIdentifier("jarvis-browser-reload")
                Button { _ = browser.hide() } label: { Image(systemName: "xmark") }
                    .accessibilityIdentifier("jarvis-browser-close")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 15)
            .frame(height: 46)
            HStack {
                Text(browser.pageTitle.isEmpty ? browser.query : browser.pageTitle)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if browser.isLoading { ProgressView().controlSize(.small) }
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 14)
            .frame(height: 30)
            Rectangle().fill(.orange.opacity(0.3)).frame(height: 1)
            if let error = browser.errorText {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(12)
            }
            JarvisEmbeddedBrowser(browser: browser, url: url)
                .background(Color.white)
                .accessibilityIdentifier("jarvis-embedded-web-view")
        }
        .background(Color(red: 0.035, green: 0.035, blue: 0.035),
                    in: RoundedRectangle(cornerRadius: 17))
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17)
            .stroke(Color.orange.opacity(0.34), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 25)
        .accessibilityIdentifier("jarvis-internal-web-browser")
    }

    private var dashboardPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(Color(red: 1, green: 0.66, blue: 0.23))
                Text("PROJECT STATUS")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    _ = dashboard.hide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("jarvis-dashboard-close")
            }
            .padding(.horizontal, 17)
            .padding(.top, 13)
            .padding(.bottom, 13)

            Rectangle().fill(Color.orange.opacity(0.35)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if dashboard.isLoading {
                        ProgressView("기록 불러오는 중…")
                            .tint(.orange)
                            .foregroundStyle(.white)
                            .padding(.vertical, 20)
                    } else if let error = dashboard.errorText {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.vertical, 20)
                    } else {
                        Text("로컬 JARVIS에 저장된 작업 · 조회 결과")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.52))
                        HStack(spacing: 0) {
                            dashboardNumber("예정", dashboard.totalTodo)
                            dashboardNumber("진행", dashboard.totalDoing)
                            dashboardNumber("막힘", dashboard.totalBlocked)
                            dashboardNumber("완료", dashboard.totalDone)
                        }
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        if dashboard.projects.isEmpty {
                            Text("등록된 프로젝트가 없습니다.")
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        ForEach(dashboard.projects) { project in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(project.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("진행 \(project.taskCounts.doing) · 예정 \(project.taskCounts.todo) · 막힘 \(project.taskCounts.blocked) · 완료 \(project.taskCounts.done)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.63))
                                if project.nextTasks.isEmpty {
                                    Text("현재 등록된 진행·예정 작업 없음")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.55))
                                } else {
                                    ForEach(project.nextTasks.prefix(4)) { task in
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Circle()
                                                .fill(task.status == "doing" ? Color.orange : Color.gray)
                                                .frame(width: 6, height: 6)
                                            Text(task.title)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.white.opacity(0.88))
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let date = dashboard.refreshedAt {
                            Text("로컬 기록 읽은 시각: \(date.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.43))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(red: 0.032, green: 0.035, blue: 0.037).opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.orange.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 25)
        .accessibilityIdentifier("jarvis-on-demand-dashboard")
    }

    private func dashboardNumber(_ label: String, _ count: Int) -> some View {
        VStack(spacing: 6) {
            Text(String(count))
                .font(.system(size: 22, weight: .light, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.54))
        }
        .frame(maxWidth: .infinity)
    }

    private func sendTyped() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedText = ""
        dialogue.submitTyped(text)
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
    private var dialogue: JarvisOverlayConversation?

    func start() {
        NSLog("JARVIS: overlay start, args=%@", ProcessInfo.processInfo.arguments.joined(separator: ","))
        let key = JarvisOverlayHotkey()
        key.onPress = { [weak self] in self?.toggle() }
        key.onEscape = { [weak self] in self?.dismiss() }
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
        let dialogue = JarvisOverlayConversation()
        self.dialogue = dialogue
        window.contentView = NSHostingView(rootView: JarvisSummonedView(
            videoURL: url,
            dismiss: { [weak self] in self?.dismiss() },
            moveToAdjacentScreen: { [weak self] direction in self?.moveToAdjacentScreen(direction) },
            dialogue: dialogue,
            dashboard: dialogue.dashboard,
            browser: dialogue.browser))
        // Do not show the old JARVIS dashboard behind the cinematic veil.
        // orderOut keeps its state and project data intact; the Dock can reopen it.
        hiddenAppWindows = NSApp.windows.filter { $0 !== window && $0.isVisible }
        for oldWindow in hiddenAppWindows { oldWindow.orderOut(nil) }
        panel = window
        if hotkey?.installEscape() != true {
            NSLog("JARVIS: global Esc hotkey unavailable; local Esc remains enabled")
        }
        NSLog("JARVIS: panel created, frame=%@", NSStringFromRect(window.frame))
        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            if event.type == .keyDown {
                // Escape must win over animation, dialogue and other overlay states.
                if event.keyCode == 53 {
                    self.dismiss()
                    return nil
                }
                // Space is the manual start/finish microphone control.
                // Do not intercept spaces typed into the text input.
                if event.keyCode == 49 && self.dialogue?.textInputFocused != true &&
                   self.dialogue?.browser.isVisible != true {
                    self.dialogue?.toggleMicrophone()
                    return nil
                }
                // Reliable fallback when trackpad gestures are unavailable.
                if (event.keyCode == 123 || event.keyCode == 124) &&
                   self.dialogue?.browser.isVisible != true {
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
            await ElevenLabsVoiceService.shared.waitForOutputToFinish(fallback: self.greetingFallback)
            guard !Task.isCancelled, self.panel != nil, self.dialogue === dialogue else { return }
            await dialogue.afterGreeting()
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
        hotkey?.uninstallEscape()
        // Highest priority: stop audio and cancel outstanding greeting requests.
        greetingTask?.cancel()
        greetingTask = nil
        dialogue?.cancel()
        dialogue = nil
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
        hotkey?.uninstallEscape()
        greetingTask?.cancel()
        greetingTask = nil
        dialogue?.cancel()
        dialogue = nil
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
