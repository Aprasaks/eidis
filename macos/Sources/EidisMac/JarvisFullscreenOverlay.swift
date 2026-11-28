import AppKit
import AVFoundation
import Carbon
import SwiftUI
import Combine

// Keyboard invocation remains available independently of the opt-in DEKA experiment.
private final class JarvisOverlayHotkey {
    private var hotkey: EventHotKeyRef?
    private var escapeHotkey: EventHotKeyRef?
    private var microphoneHotkey: EventHotKeyRef?
    private var miniHotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMicrophone: (() -> Void)?
    var onMini: (() -> Void)?

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
                case 53: key.onMicrophone?()
                case 54: key.onMini?()
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

    func installMini() -> Bool {
        guard miniHotkey == nil else { return true }
        let identifier = EventHotKeyID(signature: 0x4A415256, id: 54)
        return RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | optionKey),
            identifier, GetApplicationEventTarget(), 0, &miniHotkey) == noErr
    }

    func uninstallEscape() {
        if let escapeHotkey { UnregisterEventHotKey(escapeHotkey) }
        escapeHotkey = nil
    }

    /// Opt-Space remains available when the embedded WebKit view owns focus.
    /// This shortcut is installed ONLY while the overlay is visible.
    func installMicrophone() -> Bool {
        guard microphoneHotkey == nil else { return true }
        let identifier = EventHotKeyID(signature: 0x4A415256, id: 53)
        return RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), identifier,
            GetApplicationEventTarget(), 0, &microphoneHotkey) == noErr
    }

    func uninstallMicrophone() {
        if let microphoneHotkey { UnregisterEventHotKey(microphoneHotkey) }
        microphoneHotkey = nil
    }

    func uninstall() {
        uninstallEscape()
        uninstallMicrophone()
        if let miniHotkey { UnregisterEventHotKey(miniHotkey) }
        miniHotkey = nil
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

final class JarvisVideoSurface: NSView {
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
}

// Keep fullscreen playback separate from the SwiftUI surface. Opening casual
// chat can invalidate or remount the video NSView; it must not restart the film.
final class JarvisVideoPlayback {
    let player = AVQueuePlayer()
    private let url: URL
    private var looper: AVPlayerLooper?
    private weak var activeSurface: JarvisVideoSurface?
    private var healthTimer: Timer?
    private var previousTime: Double?
    private var lastHealthyAt = Date()
    private var repairStage = 0
    private var lastRebuildAt = Date.distantPast

    init(url: URL) {
        self.url = url
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        // Long-lived fullscreen playback can lose its visible video while the
        // SwiftUI overlay and all APIs remain responsive. Observe the *real*
        // AVPlayer timeline and display layer instead of animating a fake core.
        healthTimer = Timer.scheduledTimer(withTimeInterval: 4.3, repeats: true) { [weak self] _ in
            self?.restorePlaybackIfStalled()
        }
    }

    func attach(surface: JarvisVideoSurface) {
        activeSurface = surface
        if surface.playerLayer?.player !== player {
            surface.playerLayer?.player = player
        }
        previousTime = nil
        lastHealthyAt = Date()
        repairStage = 0
        player.play()
    }

    private func restorePlaybackIfStalled() {
        guard let surface = activeSurface, surface.window?.isVisible == true else {
            // Do not start or rebuild the player when fullscreen is hidden.
            lastHealthyAt = Date()
            previousTime = nil
            repairStage = 0
            return
        }
        let now = Date()
        let time = CMTimeGetSeconds(player.currentTime())
        let progressed: Bool
        if time.isFinite, let previousTime {
            // 10-second source loops, so backward wrap is healthy progress.
            progressed = abs(time - previousTime) > 0.08
        } else {
            progressed = false
        }
        previousTime = time.isFinite ? time : nil
        let ready = surface.playerLayer?.isReadyForDisplay == true
        if progressed && ready {
            lastHealthyAt = now
            repairStage = 0
            return
        }
        guard now.timeIntervalSince(lastHealthyAt) >= 13 else { return }

        if repairStage == 0 {
            // Recover a lost display layer and a merely paused queue first.
            surface.playerLayer?.player = nil
            surface.playerLayer?.player = player
            player.play()
            repairStage = 1
            lastHealthyAt = now
            NSLog("JARVIS: core video recovery: reattached player layer")
            return
        }
        // If the AVPlayerLooper has stopped producing items after the first
        // repair, rebuild only its queue. Never recreate the SwiftUI window.
        guard now.timeIntervalSince(lastRebuildAt) >= 60 else { return }
        lastRebuildAt = now
        looper?.disableLooping()
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
        repairStage = 0
        lastHealthyAt = now
        previousTime = nil
        NSLog("JARVIS: core video recovery: rebuilt stopped looping queue")
    }

    deinit {
        healthTimer?.invalidate()
        player.pause()
    }
}

struct JarvisLoopingCore: NSViewRepresentable {
    let videoURL: URL
    let compact: Bool
    // Owned by the fullscreen view, not by the ephemeral NSView coordinator.
    var persistentPlayback: JarvisVideoPlayback? = nil

    final class Coordinator {
        let playback: JarvisVideoPlayback
        let persistent: Bool

        init(url: URL, persistentPlayback: JarvisVideoPlayback?) {
            self.persistent = persistentPlayback != nil
            self.playback = persistentPlayback ?? JarvisVideoPlayback(url: url)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: videoURL, persistentPlayback: persistentPlayback)
    }

    func makeNSView(context: Context) -> JarvisVideoSurface {
        let view = JarvisVideoSurface(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.playerLayer?.backgroundColor = NSColor.clear.cgColor
        view.playerLayer?.isOpaque = false
        // 코어 영상의 검은 배경이 뒤의 금빛 잔해 위에 네모로 보이지 않게 '스크린' 합성 (검정 = 투명)
        view.playerLayer?.compositingFilter = "screenBlendMode"
        view.playerLayer?.videoGravity = compact ? .resizeAspectFill : .resizeAspect
        context.coordinator.playback.attach(surface: view)
        return view
    }

    func updateNSView(_ view: JarvisVideoSurface, context: Context) {
        view.playerLayer?.frame = view.bounds
        // SwiftUI updates may alter the crop, but never replace the player.
        view.playerLayer?.videoGravity = compact ? .resizeAspectFill : .resizeAspect
        if view.playerLayer?.player !== context.coordinator.playback.player {
            context.coordinator.playback.attach(surface: view)
        }
    }

    static func dismantleNSView(_ view: JarvisVideoSurface, coordinator: Coordinator) {
        view.playerLayer?.player = nil
        // Only transient secondary cores end playback on view teardown.
        // The fullscreen core keeps playing across chat/overview transitions.
        if !coordinator.persistent { coordinator.playback.player.pause() }
    }
}


/// The mini companion is intentionally just the gold core. It opens its
/// conversation on click and stays visible as a wake-word standby surface.
/// Dragging works on the core itself; hiding uses the existing mini shortcut.
private struct JarvisMiniCoreView: View {
    let videoURL: URL
    let diameter: CGFloat
    let openChat: () -> Void
    let dragCore: (CGSize) -> Void
    @State private var lastDragTranslation: CGSize = .zero

    var body: some View {
        Button(action: openChat) {
            JarvisLoopingCore(videoURL: videoURL, compact: true)
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .contentShape(Circle())
                .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("이디스 일상 채팅 열기")
        .accessibilityIdentifier("jarvis-mini-open-chat")
        .frame(width: diameter, height: diameter)
        // A drag is different from a click; no visible handle is needed.
        .simultaneousGesture(
            DragGesture(minimumDistance: 9)
                .onChanged { value in
                    let delta = CGSize(
                        width: value.translation.width - lastDragTranslation.width,
                        height: value.translation.height - lastDragTranslation.height
                    )
                    lastDragTranslation = value.translation
                    dragCore(delta)
                }
                .onEnded { _ in lastDragTranslation = .zero }
        )
        .accessibilityIdentifier("jarvis-mini-core")
    }
}

private struct JarvisSummonedView: View {
    let videoURL: URL
    let corePlayback: JarvisVideoPlayback
    let dismiss: () -> Void
    let moveToAdjacentScreen: (Int) -> Void
    @ObservedObject var dialogue: JarvisOverlayConversation
    @ObservedObject var wake: JarvisDekaWake
    @ObservedObject var dashboard: JarvisOverlayDashboard
    @ObservedObject var browser: JarvisOverlayBrowser
    @ObservedObject var vault: JarvisKnowledgeVault
    @ObservedObject var liveDashboard: JarvisLiveDashboard
    @ObservedObject var stockBoard: JarvisStockBoard
    @ObservedObject var weatherCenter: JarvisWeatherCenter
    @ObservedObject var calendar: JarvisMacCalendarStore
    @State private var typedText = ""
    @FocusState private var isInputFocused: Bool
    @State private var appeared = false
    /// 소환할 때 한 번: 설계도 선이 그어지며 금색 코어가 생기는 연출 (DECHIVE_Core_Form, 3초)
    @State private var formPlaying = JarvisCinematics.form != nil
    @State private var controlsHovered = false
    @State private var closeHovered = false
    @State private var showDiagnostics = false
    @State private var showChatMemoryReview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if dialogue.chromeWorkspaceVisible {
            chromeWorkspaceSidebar
        } else {
            standardBody
        }
    }

    private var chromeWorkspaceSidebar: some View {
        GeometryReader { area in
            let coreSize = min(area.size.width * 0.84, area.size.height * 0.32)
            VStack(spacing: 12) {
                HStack {
                    Text("DECHIVE / WORKSPACE")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                    Spacer(minLength: 4)
                    Button {
                        Task { await dialogue.returnFromChromeWorkspace() }
                    } label: {
                        Image(systemName: "rectangle.grid.2x2")
                        Text("전체 현황")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("jarvis-chrome-workspace-return")
                }
                JarvisLoopingCore(videoURL: videoURL, compact: true)
                    .frame(width: coreSize, height: coreSize)
                    .mask(RadialGradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.88),
                        .init(color: .clear, location: 1)
                    ], center: .center, startRadius: 0, endRadius: coreSize / 2))
                    .allowsHitTesting(false)
                Text(dialogue.chromeWorkspaceTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Text("기존 Chrome 세션 · 실제 브라우저")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                if !dialogue.chromeWorkspaceNotice.isEmpty {
                    Text(dialogue.chromeWorkspaceNotice).font(.caption).foregroundStyle(.orange)
                }
                workspaceConversationPanel
                    .frame(maxHeight: .infinity)
            }
            .padding(16)
            .frame(width: area.size.width, height: area.size.height)
            .background(Color.black)
        }
        .accessibilityIdentifier("jarvis-chrome-workspace-sidebar")
        .onAppear {
            isInputFocused = false
            dialogue.textInputFocused = false
        }
    }

    private var standardBody: some View {
        GeometryReader { area in
            let commandCenter = liveDashboard.isVisible && liveDashboard.mode == .overview
            let workspaceActive = !commandCenter && (dialogue.socialDashboardChannel != nil || browser.isVisible ||
                vault.isVisible || liveDashboard.isVisible || dashboard.isVisible || dialogue.briefingVisible || stockBoard.visible || weatherCenter.visible || calendar.visible)
            let compactCore = commandCenter || workspaceActive
            let conversationWidth = min(max(area.size.width * 0.30, 255), 470)
            let wide = area.size.width >= 1120
            let smallCore = min(area.size.width * (wide ? 0.253 : 0.34),
                                area.size.height * (wide ? 0.44 : 0.37))
            let overviewFrame = JarvisOverviewGeometry.coreFrame(width: area.size.width, height: area.size.height)
            let overviewCoreSize = overviewFrame.width
            ZStack {
                // Full-HD original has a black backdrop. Match it without
                // chroma-key artifacts or a visibly scaled transparency matte.
                Color.black.opacity(appeared ? 1 : 0)
                    .ignoresSafeArea()
                // 소환 연출: 코어 루프 자리에 생성 영상을 먼저 틀고, 끝나면 루프를 처음부터 이어 튼다
                if formPlaying && !commandCenter && !workspaceActive, let form = JarvisCinematics.form {
                    JarvisCinematicClip(url: form) {
                        corePlayback.player.seek(to: .zero)
                        withAnimation(.easeOut(duration: 0.2)) { formPlaying = false }
                    }
                    .frame(width: area.size.width, height: area.size.height)
                    .position(x: area.size.width / 2, y: area.size.height / 2)
                    .zIndex(10)
                    .allowsHitTesting(false)
                }
                JarvisLoopingCore(videoURL: videoURL, compact: compactCore,
                                  persistentPlayback: corePlayback)
                    .onChange(of: dialogue.formReplay) { _, _ in
                        guard JarvisCinematics.form != nil else { return }
                        formPlaying = false
                        DispatchQueue.main.async { formPlaying = true }
                    }
                    .frame(width: commandCenter ? overviewCoreSize : (compactCore ? smallCore : area.size.width),
                           height: commandCenter ? overviewCoreSize : (compactCore ? smallCore : area.size.height))
                    // Use the original stable ten-second gold core movie.
                    // Fade only the baked-in caption; never stack video effects.
                    .mask {
                        if commandCenter {
                            // Keep the complete orbit and its outer light
                            // trails. Only the far edges fade into black; a
                            // hard circular matte used to cut the visible ring.
                            RadialGradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.88),
                                .init(color: .clear, location: 1)
                            ], center: UnitPoint(x: 0.5, y: 0.47),
                               startRadius: 0, endRadius: overviewCoreSize * 0.50)

                        } else if compactCore {
                            // 글자 없는 코어(2026-11-27 교체)라 아래를 가릴 필요가 없다. 가장자리만 부드럽게.
                            RadialGradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.86),
                                .init(color: .clear, location: 1)
                            ], center: .center, startRadius: 0, endRadius: smallCore * 0.5)
                        } else {
                            // 예전 영상은 궤도 아래에 DECHIVE 글자가 박혀 있어 아래 20%를 가로로 가렸고,
                            // 그 때문에 링 아래쪽이 잘렸다. 글자 없는 블렌더 원본으로 바꿔 가림막을 없앤다.
                            Color.white
                        }
                    }
                    .position(x: commandCenter ? overviewFrame.midX : area.size.width / 2,
                              y: commandCenter ? overviewFrame.midY :
                                workspaceActive ? area.size.height * 0.17 : area.size.height / 2)
                    .opacity(dialogue.socialDashboardChannel != nil || (formPlaying && !commandCenter && !workspaceActive) ? 0
                             : (appeared ? (workspaceActive ? 0.65 : (liveDashboard.workroomProject == nil ? 1 : 0.18)) : 0))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.72), value: compactCore)
                    // In the overview this is a foreground hologram, never a
                    // child of a dashboard card. Its transparent lane keeps
                    // it away from the interactive side panels.
                    .zIndex(commandCenter ? 9 : 0)
                    .allowsHitTesting(false)

                // 실제로 일하는 에이전트가 있으면 코어 주위가 그 색으로 맥동한다 (JarvisCoreAura).
                if commandCenter && liveDashboard.workroomProject == nil && !liveDashboard.snsRoomOpen {
                    JarvisCoreAura(agentBay: dialogue.agentBay, size: overviewCoreSize)
                        .position(x: overviewFrame.midX, y: overviewFrame.midY)
                        .zIndex(8)
                }

                // The glowing core is a direct, model-free way to open
                // the same live workroom as the voice command. Clicking it
                // again in the workroom returns to the clean central core.
                if !workspaceActive && liveDashboard.workroomProject == nil && !liveDashboard.snsRoomOpen {
                    let hitDiameter = commandCenter
                        ? overviewCoreSize * 0.77
                        : min(area.size.width * 0.43, area.size.height * 0.66)
                    Button {
                        if commandCenter {
                            _ = liveDashboard.hide()
                        } else {
                            Task { _ = await liveDashboard.show(.overview) }
                        }
                    } label: {
                        Circle()
                            .fill(Color.white.opacity(0.001))
                            .contentShape(Circle())
                            .frame(width: hitDiameter, height: hitDiameter)
                    }
                    .buttonStyle(.plain)
                    .position(x: commandCenter ? overviewFrame.midX : area.size.width / 2,
                              y: commandCenter ? overviewFrame.midY : area.size.height / 2)
                    .zIndex(11)
                    .help(commandCenter ? "코어 화면으로 돌아가기" : "실시간 대시보드 열기")
                    .accessibilityLabel(commandCenter ? "코어 화면으로 돌아가기" : "실시간 대시보드 열기")
                    .accessibilityIdentifier("jarvis-core-tap-workroom-toggle")
                }

                // No reactive graphics in HOME: one stable video player only.
                // Wake-word and TTS remain available without visual overlays.

                // HOME / STANDBY intentionally shows only the orbit.
                // Dismissal is available through the menu / Command-Option-J.
                // A dashboard keeps its existing close action in its own view.
                if workspaceActive {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: dismiss) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(16)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("DECHIVE 화면 닫기")
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 30)
                    .zIndex(12)
                }

                if (workspaceActive || commandCenter) && !dialogue.chromeWorkspaceNotice.isEmpty {
                    VStack {
                        Spacer()
                        Text(dialogue.chromeWorkspaceNotice)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .padding(12)
                            .background(.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 22)
                    }
                    .allowsHitTesting(false)
                    .zIndex(15)
                }

                // A single immersive control room for the entire monitor.
                // Core is still rendered by the original, continuous AVPlayer.
                if commandCenter {
                    JarvisCommandCenterView(model: liveDashboard, dialogue: dialogue, agentBay: dialogue.agentBay) {
                        _ = liveDashboard.hide()
                    }
                    .transition(.opacity)
                    .zIndex(10)
                } else if workspaceActive {
                    // A dedicated two-column workspace: the browser, even as
                    // an NSView, can never overlap text history or the composer.
                    HStack(spacing: 16) {
                        VStack(spacing: 10) {
                            if dialogue.socialDashboardChannel != nil {
                                let diameter = min(conversationWidth * 0.80, area.size.height * 0.25)
                                JarvisLoopingCore(videoURL: videoURL, compact: true)
                                    .frame(width: diameter, height: diameter)
                                    .mask(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.88), .init(color: .clear, location: 1)], center: .center, startRadius: 0, endRadius: diameter / 2))
                                    .allowsHitTesting(false)
                            }
                            workspaceConversationPanel
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: conversationWidth)
                        .frame(maxHeight: .infinity)
                        Group {
                            if calendar.visible {
                                JarvisMacCalendarView(model: calendar, onClose: { calendar.close() })
                            } else if let channel = dialogue.socialDashboardChannel {
                                JarvisSocialDashboardView(channel: channel) {
                                    Task { await dialogue.closeNativeSocialDashboard() }
                                }.id(channel.rawValue)
                            } else if weatherCenter.visible {
                                JarvisWeatherCenterView(model:weatherCenter)
                            } else if stockBoard.visible {
                                JarvisStockBoardView(model:stockBoard)
                            } else if dialogue.briefingVisible {
                                JarvisMorningBriefingView(job:dialogue.briefingJob,
                                    notice:dialogue.briefingNotice) { dialogue.hideBriefing() }
                            } else if browser.isVisible, let url = browser.currentURL {
                                embeddedBrowserPanel(url: url)
                            } else if liveDashboard.isVisible {
                                liveDashboardPanel
                            } else if vault.isVisible {
                                knowledgeVaultPanel
                            } else if dashboard.isVisible {
                                dashboardPanel
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, max(18, area.size.width * 0.017))
                    .padding(.top, 38)
                    .padding(.bottom, 16)
                    .frame(width: area.size.width, height: area.size.height)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .zIndex(8)
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
                        // Dragging the fixed conversation workspace should
                        // never move the entire fullscreen panel away.
                        if workspaceActive || commandCenter { return }
                        if abs(value.translation.width) > 100 &&
                           abs(value.translation.width) > abs(value.translation.height) * 1.25 {
                            moveToAdjacentScreen(value.translation.width < 0 ? 1 : -1)
                        }
                    }
            )
            .onChange(of: workspaceActive) { _, _ in
                // Old text field was unmounted as we switched workspaces.
                // Never leave Space permanently disabled by a stale FocusState.
                isInputFocused = false
                dialogue.textInputFocused = false
                showDiagnostics = false
            }
        }
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.easeInOut(duration: 0.36)) { appeared = true } }
        }
    }

    private var restingControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Button { dialogue.toggleMicrophone() } label: {
                    Label(dialogue.isListening ? "질문 마치기" :
                          (dialogue.isThinking || dialogue.isSpeaking ? "끼어들기" : "대화 시작"),
                          systemImage: dialogue.isListening ? "stop.circle.fill" : "mic.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("jarvis-overlay-microphone")
                TextField("이디스에게 이야기하기", text: $typedText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($isInputFocused)
                    .onChange(of: isInputFocused) { _, focused in
                        dialogue.textInputFocused = focused
                    }
                    .onSubmit { sendTyped() }
                    .disabled(dialogue.isListening)
                    .accessibilityIdentifier("jarvis-overlay-text-input")
                Button("보내기") { sendTyped() }
                    .buttonStyle(.bordered)
                    .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dialogue.isListening)
                    .accessibilityIdentifier("jarvis-overlay-send")
                Button { showDiagnostics.toggle() } label: {
                    Image(systemName: "terminal")
                }
                .help("시스템 진단")
                .accessibilityLabel("시스템 진단")
                .popover(isPresented: $showDiagnostics, arrowEdge: .top) {
                    diagnosticsPanel
                }
            }
            .frame(maxWidth: 720)
            .padding(12)
            .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
            // Text chat must be discoverable without hunting for a hover area.
            .opacity(controlsHovered || isInputFocused || showDiagnostics || !typedText.isEmpty ? 1 : 0.93)
        }
        .frame(maxWidth: 760)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onHover { controlsHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: controlsHovered)
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("SYSTEM / VOICE", systemImage: "terminal")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(dialogue.status)
            if !dialogue.activeMicrophone.isEmpty {
                Text(dialogue.activeMicrophone)
                    .accessibilityIdentifier("jarvis-active-microphone")
            }
            if !dialogue.speechCaptureNotice.isEmpty {
                Text(dialogue.speechCaptureNotice)
                    .accessibilityIdentifier("jarvis-speech-evidence")
            }
            voicePauseMenu
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }

    private var voicePauseMenu: some View {
        Menu {
            Button("빠르게 · 1.8초") {
                dialogue.silenceWaitSeconds = 1.8
                dialogue.autoTurnEnabled = true
            }
            Button("보통 · 2.8초") {
                dialogue.silenceWaitSeconds = 2.8
                dialogue.autoTurnEnabled = true
            }
            Button("천천히 · 4.0초") {
                dialogue.silenceWaitSeconds = 4.0
                dialogue.autoTurnEnabled = true
            }
            Divider()
            Button("수동 종료 · Space") {
                dialogue.autoTurnEnabled = false
            }
        } label: {
            Text(dialogue.autoTurnEnabled ?
                "자동 \(dialogue.silenceWaitSeconds.formatted(.number.precision(.fractionLength(1))))초" :
                "수동")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.orange.opacity(0.87))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("질문 자동 종료 시간 선택")
        .accessibilityIdentifier("jarvis-voice-silence-control")
    }

    private var workspaceConversationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.orange)
                Text(dialogue.casualChatMode ? "EIDIS / 일상 채팅" : "EIDIS / CONVERSATION")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 0)
                if dialogue.casualChatMode {
                    Button("채팅 닫기") { dialogue.setCasualChatMode(false) }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("jarvis-casual-chat-close")
                }
                Button { showDiagnostics.toggle() } label: {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("시스템 진단")
                .accessibilityLabel("시스템 진단")
                .popover(isPresented: $showDiagnostics, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dialogue.status)
                        Text(dialogue.activeMicrophone)
                            .accessibilityIdentifier("jarvis-workspace-active-microphone")
                        Text(dialogue.speechCaptureNotice)
                            .accessibilityIdentifier("jarvis-workspace-speech-evidence")
                        voicePauseMenu
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(16)
                    .frame(width: 320, alignment: .leading)
                }
            }
            Rectangle().fill(.orange.opacity(0.24)).frame(height: 1)
            if dialogue.casualChatMode {
                HStack(spacing: 7) {
                    Image(systemName: "brain.head.profile")
                    Text(dialogue.learning.enabled
                         ? "대화 학습 켜짐 · 승인한 기억만 답변에 반영"
                         : "대화 학습 꺼짐 · 채팅은 계속 이용 가능")
                    Spacer(minLength: 2)
                    Button(dialogue.learning.pendingCount > 0
                           ? "기억 후보 \(dialogue.learning.pendingCount)개 검토" : "기억 설정") {
                        showChatMemoryReview = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .popover(isPresented: $showChatMemoryReview, arrowEdge: .bottom) {
                        JarvisLearningReviewView(learning: dialogue.learning)
                            .padding(16).frame(width: 350)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.62))
                .accessibilityIdentifier("jarvis-casual-chat-learning")
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(dialogue.dialogueTurns) { turn in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(turn.role == "YOU" ? "DECHIVE" :
                                     turn.interrupted ? "EIDIS / INTERRUPTED" : "EIDIS")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(turn.role == "YOU" ? .orange : .green)
                                Text(turn.content)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(turn.interrupted ? 0.6 : 0.92))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(turn.id)
                        }
                        if dialogue.isThinking && !dialogue.streamingAnswer.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("EIDIS / 작성 중 · 아직 최종 답변 아님")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.orange)
                                Text(dialogue.streamingAnswer)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.86))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if !dialogue.liveTranscript.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("YOU")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.orange)
                                Text(dialogue.liveTranscript)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if dialogue.dialogueTurns.isEmpty && !dialogue.isListening {
                            Text(dialogue.casualChatMode
                                 ? "오늘 있었던 일이나 그냥 떠오른 생각을 편하게 말해 주세요."
                                 : "브라우저를 열어도 대화 내용은 여기 남아 있습니다.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.57))
                        }
                        Color.clear.frame(height: 1).id("workspace-end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
                .scrollIndicators(.visible)
                .onChange(of: dialogue.dialogueTurns.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("workspace-end", anchor: .bottom)
                    }
                }
                .onChange(of: dialogue.liveTranscript) { _, _ in
                    proxy.scrollTo("workspace-end", anchor: .bottom)
                }
                .onChange(of: dialogue.streamingAnswer) { _, _ in
                    proxy.scrollTo("workspace-end", anchor: .bottom)
                }
            }
            if let source = dialogue.sourceURL {
                Link(dialogue.sourceTitle.isEmpty ? (source.host ?? "원문") : dialogue.sourceTitle, destination: source)
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.85))
                    .lineLimit(2)
            }
            Rectangle().fill(.white.opacity(0.13)).frame(height: 1)
            HStack(spacing: 7) {
                Button {
                    dialogue.toggleMicrophone()
                } label: {
                    Image(systemName: dialogue.isListening ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.68, green: 0.37, blue: 0.06))
                .accessibilityLabel(dialogue.isListening ? "질문 마치기" : "마이크 시작 또는 끼어들기")
                .accessibilityIdentifier("jarvis-workspace-microphone")
                TextField(dialogue.casualChatMode ? "편하게 이야기해 주세요…" : "이디스에게 질문", text: $typedText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($isInputFocused)
                    .onChange(of: isInputFocused) { _, focused in
                        dialogue.textInputFocused = focused
                    }
                    .onSubmit { sendTyped() }
                    .disabled(dialogue.isListening)
                    .accessibilityIdentifier("jarvis-workspace-text-input")
                Button { sendTyped() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          dialogue.isListening)
                .accessibilityLabel("질문 보내기")
                .accessibilityIdentifier("jarvis-workspace-send")
            }
            Text("⌥ Space: 언제든 음성 · Space: 입력 중이 아닐 때")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.035, green: 0.042, blue: 0.055).opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.orange.opacity(0.34), lineWidth: 1))
        .accessibilityIdentifier("jarvis-workspace-conversation")
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
                Button { Task { await dialogue.closeSocialProfile() } } label: { Image(systemName: "xmark") }
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
            if !browser.lastControlReceipt.isEmpty {
                VStack(alignment: .leading,spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "cursorarrow.click.2")
                        Text("BROWSER CONTROL / 실제 동작 확인")
                            .fontWeight(.semibold)
                        Spacer(minLength: 0)
                    }
                    Text(browser.lastControlReceipt)
                        .lineLimit(2)
                    if !browser.observedLinks.isEmpty {
                        Text(browser.observedLinks.prefix(4).map {
                            "\($0.number). \($0.title)"
                        }.joined(separator: "  ·  "))
                            .lineLimit(2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .font(.system(size: 9,design: .monospaced))
                .foregroundStyle(.orange.opacity(0.87))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .frame(maxWidth:.infinity,alignment:.leading)
                .accessibilityIdentifier("dechive-browser-control-receipt")
            }
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

    /// A request-driven library next to the unchanged golden core, not a new
    /// permanent dashboard or an extra home screen.
    private var knowledgeVaultPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "books.vertical")
                    .foregroundStyle(Color.orange)
                Text("DECHIVE · 보관함")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { _ = vault.hide() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("jarvis-vault-close")
            }
            .padding(16)
            Rectangle().fill(.orange.opacity(0.3)).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(vault.searchLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text("검색 결과 \(vault.total)건 · 이 Mac에만 저장 · 실제 자료 목록")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.62))
                if !vault.counts.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                        ForEach(JarvisKnowledgeVault.categoryOrder, id: \.self) { category in
                            if let count = vault.counts[category], count > 0 {
                                Text("\(JarvisKnowledgeVault.labels[category] ?? category) \(count)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange.opacity(0.9))
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(.white.opacity(0.065), in: Capsule())
                            }
                        }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 11) {
                    if vault.isLoading {
                        ProgressView("로컬 자료 조회 중…")
                            .tint(.orange)
                            .foregroundStyle(.white)
                    } else if let error = vault.errorText {
                        Text(error).foregroundStyle(.white)
                    } else if let item = vault.selectedItem {
                        vaultItemCard(item, full: true)
                    } else if vault.items.isEmpty {
                        Text("아직 저장된 자료가 없습니다. 자료 내용을 말씀하고 '저장해 줘'라고 해보세요.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.76))
                    } else {
                        ForEach(JarvisKnowledgeVault.categoryOrder, id: \.self) { category in
                            let found = vault.items.filter { $0.category == category }
                            if !found.isEmpty {
                                HStack {
                                    Text(JarvisKnowledgeVault.labels[category] ?? category)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Text("\(found.count)건")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(.top, 8)
                                ForEach(found) { item in
                                    vaultItemCard(item, full: false)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
            }
            .scrollIndicators(.visible)
        }
        .background(Color(red: 0.035, green: 0.035, blue: 0.036).opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(Color.orange.opacity(0.34), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 24)
        .accessibilityIdentifier("jarvis-vault-panel")
    }

    private func vaultItemCard(_ item: JarvisVaultItem, full: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(item.id) · \(item.categoryLabel)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.86))
                Spacer()
                if !item.project.isEmpty {
                    Text(item.project).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }
            }
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(full ? item.content : String(item.content.prefix(190)))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(full ? nil : 5)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(item.evidenceLabel)
                Text(item.createdAt.prefix(10))
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
            if !item.tags.isEmpty {
                Text(item.tags.map { "#" + $0 }.joined(separator: "  "))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange.opacity(0.68))
                    .lineLimit(2)
            }
            if !item.sourceUrl.isEmpty {
                Text("출처: \(item.sourceUrl)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(full ? nil : 2)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(.white.opacity(0.10), lineWidth: 1))
    }

    /// Live data panels appear only in response to the corresponding spoken
    /// request; the original fullscreen gold core stays untouched.
    private var liveDashboardPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundStyle(.orange)
                Text("DECHIVE / \(liveDashboard.mode.title)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button { _ = liveDashboard.hide() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("jarvis-live-dashboard-close")
            }
            .padding(16)
            Rectangle().fill(.orange.opacity(0.4)).frame(height: 1)
            HStack(spacing: 7) {
                Circle()
                    .fill(liveDashboard.errorText == nil ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(liveDashboard.errorText == nil ? "LIVE · 로컬 자료" : "부분 연결 실패")
                Spacer()
                Text("7초 간격 자동 갱신")
                if liveDashboard.isRefreshing { ProgressView().controlSize(.mini).tint(.orange) }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    if liveDashboard.isLoading {
                        ProgressView("실제 데이터 읽는 중…")
                            .tint(.orange)
                            .foregroundStyle(.white)
                            .padding(.vertical, 25)
                    } else {
                        if let warning = liveDashboard.errorText {
                            Text(warning)
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                        if liveDashboard.mode == .overview || liveDashboard.mode == .projects {
                            liveProjectSection
                        }
                        if liveDashboard.mode == .overview || liveDashboard.mode == .knowledge {
                            liveKnowledgeSection
                        }
                        if liveDashboard.mode == .overview || liveDashboard.mode == .system {
                            liveSystemSection
                        }
                        if let date = liveDashboard.refreshedAt {
                            Text("마지막 데이터 확인: \(date.formatted(date: .abbreviated, time: .standard))")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.54))
                                .padding(.top, 7)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
            }
            .scrollIndicators(.visible)
        }
        .background(Color(red: 0.038, green: 0.035, blue: 0.035).opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.orange.opacity(0.32), lineWidth: 1))
        .shadow(color: .black.opacity(0.57), radius: 25)
        .accessibilityIdentifier("jarvis-live-dashboard-panel")
    }

    private var liveProjectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            liveSectionHeader("PROJECTS · 로컬 프로젝트 원장")
            if !liveDashboard.projectsReady {
                Text("프로젝트 원장 연결 실패 · 실제 값 확인 필요")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            } else {
            HStack(spacing: 8) {
                liveStat("프로젝트", (liveDashboard.projects.count))
                liveStat("전체 작업", (liveDashboard.taskTotal))
                liveStat("완료", (liveDashboard.done))
            }
            HStack(spacing: 8) {
                liveStat("예정", (liveDashboard.todo))
                liveStat("진행", (liveDashboard.doing))
                liveStat("막힘", (liveDashboard.blocked))
            }
            if liveDashboard.projects.isEmpty {
                Text("등록된 프로젝트가 없거나 프로젝트 자료를 가져오지 못했습니다.")
                    .foregroundStyle(.white.opacity(0.65))
                    .font(.system(size: 11))
            }
            ForEach(liveDashboard.projects) { project in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(project.name).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("완료 \(project.taskCounts.done)/\(project.tasks.count)")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                    }
                    liveProgress(project.taskCounts.done, total: project.tasks.count)
                    if let next = project.nextTasks.first {
                        Text("다음 기록: \(next.title)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(2)
                    }
                }
                .padding(11)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            }
        }
    }

    private var liveKnowledgeSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            liveSectionHeader("KNOWLEDGE · 로컬 자료 보관함")
            if let total = liveDashboard.vaultTotal {
                HStack(spacing: 8) {
                    liveStat("활성 자료", (total))
                    liveStat("분류 수", (liveDashboard.vaultCounts.count))
                }
                if total == 0 {
                    Text("현재 활성 보관함에 저장된 자료가 없습니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    ForEach(JarvisKnowledgeVault.categoryOrder, id: \.self) { kind in
                        if let count = liveDashboard.vaultCounts[kind], count > 0 {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(JarvisKnowledgeVault.labels[kind] ?? kind)
                                    Spacer()
                                    Text(String(count))
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.82))
                                liveProgress(count, total: total)
                            }
                        }
                    }
                    liveSectionHeader("최근 저장 자료")
                    ForEach(liveDashboard.recentItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("#\(item.id) · \(item.title)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text("\(item.categoryLabel) · \(item.evidenceLabel)")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange.opacity(0.8))
                        }
                    }
                }
            } else {
                Text("보관함 데이터 연결 실패 · 실제 값 확인 필요")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var liveSystemSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            liveSectionHeader("SYSTEM · 로컬 시스템 진단")
            liveSystemRow("SQLite 데이터베이스", liveDashboard.databaseStatus == nil
                ? "확인 불가" : (liveDashboard.databaseStatus == "ok" ? "정상 확인" : "주의 · \(liveDashboard.databaseStatus!)"))
            liveSystemRow("Qwen 서비스 / Ollama", liveDashboard.ollamaChecked
                ? (liveDashboard.ollamaVersion.map { "연결됨 · \($0)" } ?? "연결 안 됨") : "확인 중")
            liveSystemRow("확정 사용자 프로필", liveDashboard.profileCount.map { "\($0)개" } ?? "확인 불가")
            Text("서버 진단 및 설치된 Ollama API 응답을 읽은 결과입니다. GPU·메모리 사용량은 측정하지 않았습니다.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func liveSystemRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.white).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 11))
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func liveSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(.orange)
            .padding(.bottom, 2)
    }

    private func liveStat(_ name: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(count))
                .font(.system(size: 21, weight: .light, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(name).font(.system(size: 10)).foregroundStyle(.white.opacity(0.56))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private func liveProgress(_ value: Int, total: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                Capsule().fill(.orange.opacity(0.86))
                    .frame(width: geo.size.width * CGFloat(value) / CGFloat(max(total, 1)))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("\(value) / \(total)")
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
                        Text("로컬 DECHIVE에 저장된 작업 · 조회 결과")
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
final class JarvisFullscreenOverlay: ObservableObject {
    @Published private(set) var miniEnabled =
        UserDefaults.standard.bool(forKey: "jarvis.mini.enabled")
    // Persistent opt-in: launch and wake restore the user-selected preference.
    @Published private(set) var dekaEnabled = false
    @Published private(set) var dekaArmed = false
    @Published private(set) var dekaStatus = "Jarvis 상시 대기 꺼짐"
    private let deka = JarvisDekaWake()
    private let dekaPreferenceKey = "jarvis.deka.autoStandby"
    // One-time transition to mini-owned wake standby. The menu's subsequent
    // explicit off selection is respected on future launches.
    private let miniWakeMigrationKey = "jarvis.mini.autoWakeV1"
    private var dekaSleepObserver: NSObjectProtocol?
    private var dekaWakeObserver: NSObjectProtocol?
    private var dekaResumeTask: Task<Void,Never>?
    private var chromeFullscreenFrame: NSRect?
    private var dekaSleeping = false
    private var dekaMonitorTask: Task<Void, Never>?
    private var dekaNotBefore = Date.distantPast

    // Pause capture without revoking the opt-in during a normal dialogue.
    private func pauseDeka(_ reason: String = "대화 중 · 호출 감지 일시정지") {
        if deka.armed { deka.stop(reason) }
        else if dekaEnabled && dekaStatus != reason { dekaStatus = reason }
        dekaNotBefore = Date().addingTimeInterval(0.6)
    }
    func stopDeka(_ reason: String = "Jarvis 상시 대기 꺼짐") {
        dekaEnabled = false
        dekaMonitorTask?.cancel()
        dekaMonitorTask = nil
        dialogue?.endWakeSession()
        miniDialogue?.endWakeSession()
        dialogue?.wakeStandbyEnabled = false
        miniDialogue?.wakeStandbyEnabled = false
        if deka.armed { deka.stop(reason) }
        dekaStatus = reason
    }
    private func bindDeka(_ voice: JarvisOverlayConversation) {
        voice.wakeStandbyEnabled = dekaEnabled
        voice.onBeforeQuestion = { [weak self] in self?.pauseDeka() }
    }
    func toggleDeka() {
        if dekaEnabled {
            UserDefaults.standard.set(false, forKey: dekaPreferenceKey)
            dekaResumeTask?.cancel()
            stopDeka()
            return
        }
        UserDefaults.standard.set(true, forKey: dekaPreferenceKey)
        startPreferredDeka()
    }
    private func startPreferredDeka() {
        guard !dekaEnabled, !dekaSleeping,
              UserDefaults.standard.bool(forKey: dekaPreferenceKey) else { return }
        // Local wake detection is independent of the app currently in front.
        // Other macOS windows must not prevent standby.
        // At the three-screen desk the full HOME is the visible companion.
        // Don't spawn a second floating core just to arm the microphone.
        let atHomeDesk = JarvisDisplayRoles.hasHouseholdArrangement()
        if !atHomeDesk && !miniEnabled {
            miniEnabled = true
            UserDefaults.standard.set(true, forKey: "jarvis.mini.enabled")
        }
        if panel == nil && miniPanel == nil {
            if atHomeDesk {
                dekaStatus = "HOME 화면 연결 대기 중…"
                return
            }
            showMini()
        }
        guard let voice = dialogue ?? miniDialogue else {
            dekaStatus = "코어를 열 수 없습니다."; return
        }
        dekaEnabled = true
        bindDeka(voice)
        // Explicitly switch an empty continuous-listening turn into wake
        // standby. A turn containing words is allowed to finish normally.
        if voice.isListening && voice.liveTranscript.isEmpty { voice.pauseMicrophone() }
        dekaStatus = "Jarvis 상시 대기 준비 중…"
        dekaNotBefore = Date()
        dekaMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.dekaEnabled else { return }
                await self.reconcileDeka()
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            }
        }
    }
    private func reconcileDeka() async {
        guard dekaEnabled, !Task.isCancelled else { return }
        guard let voice = dialogue ?? miniDialogue else {
            pauseDeka("코어 전환 중"); return
        }
        // Keep wake detection active while the AI thinks, invokes tools or
        // speaks. Otherwise a fresh "자비스" would be ignored precisely
        // when the user is trying to interrupt it.
        // Yield ONLY when full microphone transcription is underway.
        if voice.microphoneCaptureBusy {
            pauseDeka("음성 받아쓰기 중 · 이디스 호출은 받아쓰기로 감지")
            return
        }
        guard Date() >= dekaNotBefore, !deka.armed else { return }
        await deka.start()
    }

    private var hotkey: JarvisOverlayHotkey?
    private var panel: JarvisOverlayPanel?
    private var detachedChatPanel: JarvisOverlayPanel?
    private var detachedChatCloseObserver: NSObjectProtocol?
    private var miniPanel: JarvisOverlayPanel?
    private var miniDialogue: JarvisOverlayConversation?
    private var miniObservers: [NSObjectProtocol] = []
    private var miniDiameter: CGFloat = 190
    private var lastMiniToggle = Date.distantPast
    private var interactionMonitor: Any?
    private var lastScrollInput = Date.distantPast
    private var horizontalScrollTotal: CGFloat = 0
    private var lastMove = Date.distantPast
    private var lastToggle = Date.distantPast
    private var lastMicrophoneShortcut = Date.distantPast
    private var hiddenAppWindows: [NSWindow] = []
    private let greetingFallback = JarvisVoiceService()
    private var greetingTask: Task<Void, Never>?
    private var dialogue: JarvisOverlayConversation?
    var onPresentationChanged: ((Bool) -> Void)?

    func start() {
        JarvisDisplayRoles.registerConnectedScreens()
        deka.onStatus = { [weak self] text in
            guard let self else { return }
            self.dekaArmed = self.deka.armed
            self.dekaStatus = text
            NSLog("DEKA standby: %@", text)
            // System telemetry belongs in the menu, not the core caption.
        }
        deka.onFailure = { [weak self] reason in self?.stopDeka(reason) }
        deka.onHit = { [weak self] in
            guard let self, self.dekaEnabled,
                  let voice=self.dialogue ?? self.miniDialogue else { return }
            // The wake has priority over current speech or unfinished replies.
            self.greetingTask?.cancel()
            self.greetingTask = nil
            self.greetingFallback.stop()
            ElevenLabsVoiceService.shared.stopSpeakingNow()
            // The small always-on core opens only its companion chat.
            // A wake event never promotes the mini into fullscreen.
            if self.panel == nil && self.miniPanel != nil {
                self.openMiniCasualChat()
            }
            self.onPresentationChanged?(true)
            voice.beginDekaWakeTurn()
        }
        LocalSpeechListener.beforeCapture = { [weak self] in self?.pauseDeka("질문 듣는 중 · 받아쓰기로 호출 감지") }
        dekaSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.dekaSleeping = true
                self.dekaResumeTask?.cancel()
                self.stopDeka("절전으로 상시 대기 일시정지")
            }
        }
        dekaWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.dekaSleeping = false
                self.dekaResumeTask?.cancel()
                self.dekaResumeTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    self?.startPreferredDeka()
                }
            }
        }
        NSLog("JARVIS: overlay start, args=%@", ProcessInfo.processInfo.arguments.joined(separator: ","))
        let key = JarvisOverlayHotkey()
        key.onPress = { [weak self] in self?.toggle() }
        key.onEscape = { [weak self] in self?.escapeOneStep() }
        key.onMicrophone = { [weak self] in self?.handleMicrophoneShortcut() }
        key.onMini = { [weak self] in self?.toggleMini() }
        if key.install() {
            hotkey = key
            NSLog("JARVIS: Command-Option-J fullscreen shortcut registered")
            NSLog("JARVIS: Command-Option-S mini shortcut registered=%@", key.installMini().description)
        } else {
            NSLog("JARVIS: Command-Option-J shortcut unavailable; overlay not activated")
        }
        if miniEnabled {
            // The user opted into an always-ready mini companion. Adopt wake
            // standby once, preserving any later manual microphone opt-out.
            if !UserDefaults.standard.bool(forKey: miniWakeMigrationKey) &&
               !ProcessInfo.processInfo.arguments.contains("--overlay-preview") {
                UserDefaults.standard.set(true, forKey: miniWakeMigrationKey)
                UserDefaults.standard.set(true, forKey: dekaPreferenceKey)
            }
            showMini()
        }
        if !ProcessInfo.processInfo.arguments.contains("--overlay-preview") {
            startPreferredDeka()
        }
        // A real three-screen home desk starts HOME on the verified left LG,
        // but a MacBook-only launch remains unobtrusive. Explicit inspection
        // and preview launch modes retain their specialized behavior.
        if JarvisDisplayRoles.hasHouseholdArrangement() &&
           !ProcessInfo.processInfo.arguments.contains("--overlay-preview") &&
           !ProcessInfo.processInfo.arguments.contains("--dashboard-inspection") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.panel == nil else { return }
                self.show()
            }
        }
        // Explicit local visual inspection: open the live overview without
        // synthesizing speech, forwarding audio, or beginning a voice turn.
        // Ordinary launches and the enrolled wake profile are unchanged.
        if ProcessInfo.processInfo.arguments.contains("--dashboard-inspection") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                guard let self else { return }
                self.show()
                self.greetingTask?.cancel()
                self.greetingTask = nil
                ElevenLabsVoiceService.shared.stopSpeakingNow()
                self.greetingFallback.stop()
                if let voice = self.dialogue {
                    Task { _ = await voice.liveDashboard.show(.overview) }
                }
            }
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
        if panel == nil { show() }
        else if dialogue?.chromeWorkspaceVisible == true {
            if let dialogue { Task { await dialogue.returnFromChromeWorkspace() } }
        } else { dismiss() }
    }

    func toggleMini() {
        guard Date().timeIntervalSince(lastMiniToggle) > 0.35 else { return }
        lastMiniToggle = Date()
        miniEnabled.toggle()
        UserDefaults.standard.set(miniEnabled, forKey: "jarvis.mini.enabled")
        if miniEnabled {
            // Turning on the companion is the user's explicit standby choice.
            UserDefaults.standard.set(true, forKey: miniWakeMigrationKey)
            UserDefaults.standard.set(true, forKey: dekaPreferenceKey)
            if panel == nil { showMini() }
            startPreferredDeka()
        } else {
            if panel == nil {
                UserDefaults.standard.set(false, forKey: dekaPreferenceKey)
                stopDeka("작은 코어 숨김 · 상시 대기 종료")
            }
            hideMini()
        }
    }

    private func showMini() {
        guard miniEnabled, panel == nil else { return }
        if let miniPanel { miniPanel.orderFrontRegardless(); return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let url = Bundle.main.url(forResource: "DECHIVE_FullHD_Loop",
                                        withExtension: "mp4") else { return }
        let preferences = UserDefaults.standard
        let savedSize = preferences.object(forKey: "jarvis.mini.diameter") as? Double ?? 190
        miniDiameter = CGFloat(savedSize.isFinite ? min(max(savedSize, 160), 340) : 190)
        let size = NSSize(width: miniDiameter, height: miniDiameter)
        var frame = Self.miniFrame(visible: screen.visibleFrame, size: size)
        if let saved = preferences.string(forKey: "jarvis.mini.frame") {
            let old = NSRectFromString(saved)
            if let destination = NSScreen.screens.first(where: { $0.visibleFrame.intersects(old) }) {
                frame = Self.clampMini(NSRect(x: old.minX, y: old.maxY-size.height,
                    width: size.width, height: size.height), visible: destination.visibleFrame)
            }
        }
        let mini = JarvisOverlayPanel(contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        mini.isOpaque = false
        mini.backgroundColor = .clear
        mini.hasShadow = false
        mini.hidesOnDeactivate = false
        mini.level = .floating
        mini.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        mini.isMovableByWindowBackground = true
        let voice = JarvisOverlayConversation()
        voice.miniSingleTurn = true
        bindDeka(voice)
        voice.prepareMiniStandby()
        voice.onMiniTurnEnded = { [weak self] in
            if self?.panel == nil { self?.onPresentationChanged?(false) }
        }
        voice.onWorkspaceRequested = { [weak self] in self?.promoteMini() }
        voice.onCasualChatModeChanged = { [weak self] enabled in
            if enabled { self?.showDetachedChat() }
            else { self?.closeDetachedChat() }
        }
        miniDialogue = voice
        miniPanel = mini
        mountMini(url: url)
        miniObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: mini, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.saveMiniFrame() }
        })
        miniObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.layoutMini() }
        })
        mini.orderFrontRegardless()
        if hotkey?.installMicrophone() != true {
            NSLog("JARVIS: mini Option-Space unavailable; chat microphone is available when opened")
        }
        NSLog("JARVIS: opt-in mini core shown")
    }

    private func mountMini(url: URL) {
        guard let miniPanel, miniDialogue != nil else { return }
        miniPanel.contentView = NSHostingView(rootView: JarvisMiniCoreView(
            videoURL: url, diameter: miniDiameter,
            openChat: { [weak self] in self?.openMiniCasualChat() },
            dragCore: { [weak self] delta in self?.dragMiniCore(by: delta) }))
    }

    private func dragMiniCore(by delta: CGSize) {
        guard let miniPanel else { return }
        let frame = miniPanel.frame
        let visible = (miniPanel.screen ?? NSScreen.main)?.visibleFrame ?? frame
        let moved = NSRect(x: frame.minX + delta.width,
                           y: frame.minY - delta.height,
                           width: frame.width, height: frame.height)
        miniPanel.setFrame(Self.clampMini(moved, visible: visible), display: true)
    }

    static func clampMini(_ frame: NSRect, visible: NSRect) -> NSRect {
        NSRect(x: min(max(frame.minX,visible.minX),max(visible.minX,visible.maxX-frame.width)),
               y: min(max(frame.minY,visible.minY),max(visible.minY,visible.maxY-frame.height)),
               width: frame.width, height: frame.height)
    }

    static func miniFrame(visible: NSRect, size: NSSize) -> NSRect {
        clampMini(NSRect(x: visible.maxX-size.width-22, y: visible.minY+24,
                         width:size.width,height:size.height), visible:visible)
    }

    private func saveMiniFrame() {
        guard let miniPanel else { return }
        UserDefaults.standard.set(NSStringFromRect(miniPanel.frame), forKey: "jarvis.mini.frame")
        UserDefaults.standard.set(Double(miniDiameter), forKey: "jarvis.mini.diameter")
    }

    private func layoutMini() {
        guard let miniPanel else { return }
        let old=miniPanel.frame
        let height = miniDiameter
        let proposed = NSRect(x:old.minX,y:old.maxY-height,width:miniDiameter,height:height)
        let visible=(miniPanel.screen ?? NSScreen.main)?.visibleFrame ?? old
        miniPanel.setFrame(Self.clampMini(proposed,visible:visible),display:true)
        saveMiniFrame()
    }

    private func hideMini(preserveDialogue: Bool = false) {
        pauseDeka("코어 전환 중")
        guard let miniPanel else { return }
        miniDialogue?.onCasualChatModeChanged = nil
        miniDialogue?.setCasualChatMode(false)
        closeDetachedChat()
        saveMiniFrame()
        for observer in miniObservers { NotificationCenter.default.removeObserver(observer) }
        miniObservers.removeAll()
        if !preserveDialogue {
            miniDialogue?.cancel()
            onPresentationChanged?(false)
        }
        miniDialogue = nil
        miniPanel.orderOut(nil)
        miniPanel.contentView = nil
        self.miniPanel = nil
        hotkey?.uninstallMicrophone()
    }

    private func promoteMini() {
        guard panel == nil, let voice = miniDialogue else { return }
        present(fullscreenDialogue: voice)
    }

    private func handleMicrophoneShortcut() {
        pauseDeka("수동 마이크 전환")
        guard panel != nil || miniPanel != nil, Date().timeIntervalSince(lastMicrophoneShortcut) > 0.25 else {
            return
        }
        lastMicrophoneShortcut = Date()
        if greetingTask != nil {
            greetingTask?.cancel()
            greetingTask = nil
            ElevenLabsVoiceService.shared.stopSpeakingNow()
            greetingFallback.stop()
        }
        if let dialogue { dialogue.toggleMicrophone() }
        else if let miniDialogue {
            onPresentationChanged?(true)
            miniDialogue.toggleMicrophone()
        }
    }

    func show() {
        if miniDialogue != nil { promoteMini() }
        else { present(fullscreenDialogue: nil) }
    }

    /// "Hey JARVIS" 백그라운드 호출 (jarvis-mac://wake-dashboard · tools/wakeword/jarvis_wake_daemon.py).
    /// 자비스가 꺼져 있었으면 macOS가 앱을 켜고 이 함수로 들어온다.
    /// 2026-11-28 사용자 지정 순서: 코어 소환 → 흰빛에서 금빛으로 (DECHIVE_Core_Form 3초)
    /// → 금빛이 될 때 "Welcome home, DECHIVE." → 대시보드.
    private var wakeTask: Task<Void, Never>?
    /// 호출 인사 전용 목소리. 말하는 동안 해제되지 않도록 붙잡아 둔다.
    private lazy var wakeVoice = JarvisVoiceService()
    func wakeToDashboard() {
        guard wakeTask == nil else { return }
        NSLog("JARVIS: wake word → core form → dashboard")
        let started = Date()
        show()
        NSApp.activate(ignoringOtherApps: true)
        // 대시보드가 이미 떠 있으면 내리고, 코어 생성 연출을 처음부터 다시 튼다.
        if let dialogue, dialogue.liveDashboard.isVisible { _ = dialogue.liveDashboard.hide() }
        dialogue?.formReplay += 1
        wakeTask = Task { @MainActor [weak self] in
            defer { self?.wakeTask = nil }
            // 생성 영상은 약 2초에 금빛으로 바뀐다. 그 순간에 맞춰 인사한다.
            try? await Task.sleep(for: .milliseconds(1_700))
            let line = JarvisConversationLanguage.homeGreeting
            let voice = self?.wakeVoice
            if JarvisConversationLanguage.english, await JarvisKokoroVoice.shared.speak(line) {
            } else {
                voice?.speak(line)
            }
            // 이디스가 말을 끝낸 뒤에 대시보드를 연다 — 대시보드 받아쓰기가 이디스 목소리를 듣지 않도록
            try? await Task.sleep(for: .milliseconds(150))
            for _ in 0..<60 where voice?.isSpeaking == true {
                try? await Task.sleep(for: .milliseconds(100))
            }
            // 금빛 코어를 잠깐 보여 준 뒤 (호출 후 최소 3.6초) 대시보드로
            let shown = Date().timeIntervalSince(started)
            if shown < 3.6 { try? await Task.sleep(for: .milliseconds(Int((3.6 - shown) * 1000))) }
            guard let dialogue = self?.dialogue else { return }
            if !(dialogue.liveDashboard.isVisible && dialogue.liveDashboard.mode == .overview) {
                _ = await dialogue.liveDashboard.show(.overview)
            }
        }
    }

    private func present(fullscreenDialogue: JarvisOverlayConversation?) {
        NSLog("JARVIS: show requested")
        guard panel == nil,
              let screen = JarvisDisplayRoles.screen(for: .home),
              let url = Bundle.main.url(forResource: "DECHIVE_FullHD_Loop", withExtension: "mp4")
        else {
            NSLog("JARVIS: fullscreen video asset or active screen missing")
            return
        }
        // Release the small video player before the fullscreen player starts.
        // The opt-in preference is retained and the mini recreates on dismiss.
        let continuingActiveTurn = fullscreenDialogue?.wakeCaptureBusy == true
        hideMini(preserveDialogue: fullscreenDialogue != nil)
        // Cancel a background study request before starting live interaction.
        onPresentationChanged?(true)
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
        let dialogue = fullscreenDialogue ?? JarvisOverlayConversation()
        dialogue.miniSingleTurn = false
        bindDeka(dialogue)
        dialogue.onWorkspaceRequested = nil
        dialogue.onMiniTurnEnded = nil
        dialogue.onChromeWorkspaceOpen = { [weak self, weak dialogue] channel, channelID in
            guard let self, let dialogue else { return false }
            return await self.openChromeWorkspace(channel, channelID: channelID, dialogue: dialogue)
        }
        dialogue.onChromeWorkspaceClose = { [weak self] in self?.restoreChromeWorkspaceFrame() }
        // DevTools auto-connect asks the human through a Chrome-owned dialog.
        // Temporarily lower the screenSaver overlay so the user can see and
        // approve/deny that dialog. Never click or bypass it programmatically.
        dialogue.onChromeVerificationBegin = { [weak self] in
            self?.panel?.level = .normal
            if let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first {
                chrome.activate(options: [.activateAllWindows])
            }
        }
        dialogue.onChromeVerificationEnd = { [weak self] in
            guard let panel = self?.panel else { return }
            panel.level = .screenSaver
            panel.orderFrontRegardless()
        }
        self.dialogue = dialogue
        // Fullscreen is a task dashboard, not a second casual-chat entrypoint.
        // This player survives SwiftUI chat rebuilds; releasing the root view
        // at fullscreen dismissal releases the player and AVPlayerLooper.
        let corePlayback = JarvisVideoPlayback(url: url)
        window.contentView = NSHostingView(rootView: JarvisSummonedView(
            videoURL: url,
            corePlayback: corePlayback,
            dismiss: { [weak self] in self?.dismiss() },
            moveToAdjacentScreen: { [weak self] direction in self?.moveToAdjacentScreen(direction) },
            dialogue: dialogue,
            wake: deka,
            dashboard: dialogue.dashboard,
            browser: dialogue.browser,
            vault: dialogue.vault,
            liveDashboard: dialogue.liveDashboard, stockBoard: dialogue.stockBoard,
            weatherCenter: dialogue.weatherCenter, calendar: dialogue.calendar))
        // Do not show the old JARVIS dashboard behind the cinematic veil.
        // orderOut keeps its state and project data intact; the Dock can reopen it.
        hiddenAppWindows = NSApp.windows.filter { $0 !== window && $0.isVisible }
        for oldWindow in hiddenAppWindows { oldWindow.orderOut(nil) }
        panel = window
        // HOME owns the only wake listener when no floating mini is present.
        if !dekaEnabled && UserDefaults.standard.bool(forKey: dekaPreferenceKey) {
            startPreferredDeka()
        }
        // JARVIS HOME is always-on beside the primary workspace: do not
        // capture global Escape while GPT, Codex or Finder have keyboard focus.
        // Command-Option-J still dismisses this window explicitly.
        if hotkey?.installMicrophone() != true {
            NSLog("JARVIS: global Option-Space hotkey unavailable; local key monitor remains enabled")
        }
        NSLog("JARVIS: panel created, frame=%@", NSStringFromRect(window.frame))
        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            // Text editing and scrolling in the detached chat belong only to
            // that window, never to fullscreen navigation or core hotkeys.
            if event.window === self.detachedChatPanel { return event }
            if event.type == .keyDown {
                // Escape must win over animation, dialogue and other overlay states.
                if event.keyCode == 53 {
                    self.escapeOneStep()
                    return nil
                }
                // Option-Space is always voice-first, even when WKWebView has
                // key focus. Normal Space is typing when an editable field is
                // focused (either local composer or the embedded website).
                let nativeEditorFocused = event.window?.firstResponder is NSTextView ||
                    event.window?.firstResponder is NSTextField
                if JarvisVoiceShortcutPolicy.handles(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags,
                    composerEditing: self.dialogue?.textInputFocused == true || nativeEditorFocused,
                    browserEditing: self.dialogue?.browser.isEditingWebText == true,
                    isRepeat: event.isARepeat
                ) {
                    self.handleMicrophoneShortcut()
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
        // Do not activate JARVIS or steal keyboard focus from the work monitor.
        // The panel remains interactive when the user clicks its dashboard.
        // Keep window opacity at 1; animate SwiftUI contents instead. Fading the
        // window itself can leave a background NSPanel offscreen on macOS.
        window.alphaValue = 1
        window.orderFrontRegardless()
        NSLog("JARVIS: overlay ordered front, isVisible=%@ alpha=%.2f appHidden=%@",
              window.isVisible.description, window.alphaValue, NSApp.isHidden.description)
        // Quiet HOME standby: no automatic greeting, Qwen request or speech
        // recognition session when the large gold core first appears.
        // The shared local wake engine handles "자비스".
        greetingTask?.cancel()
        if continuingActiveTurn {
            dialogue.resumeFullWorkspace()
        } else {
            dialogue.prepareHomeStandby()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSLog("JARVIS: overlay stable, isVisible=%@ alpha=%.2f appHidden=%@",
                  window.isVisible.description, window.alphaValue, NSApp.isHidden.description)
        }
    }

    /// A standalone chat anchored to the MINI core. A wake hit opens this
    /// panel but does not change the core window or promote fullscreen.
    private func openMiniCasualChat() {
        guard panel == nil, miniPanel != nil, let miniDialogue else { return }
        miniDialogue.setCasualChatMode(true)
    }

    private func showDetachedChat() {
        guard panel == nil, let miniPanel, let miniDialogue else { return }
        if let existing = detachedChatPanel {
            existing.orderFrontRegardless()
            existing.makeKey()
            return
        }
        guard let screen = miniPanel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: min(550, max(390, visible.width * 0.37)),
                          height: min(720, max(390, visible.height * 0.78)))
        // Prefer the space to the left of the mini core. On narrow screens,
        // use the opposite side and clamp to the visible desktop work area.
        let left = miniPanel.frame.minX - size.width - 14
        let right = miniPanel.frame.maxX + 14
        let preferredX = left >= visible.minX + 8 ? left : right
        let x = min(max(preferredX, visible.minX + 8),
                    max(visible.minX + 8, visible.maxX - size.width - 8))
        let y = min(max(miniPanel.frame.midY - size.height / 2, visible.minY + 8),
                    max(visible.minY + 8, visible.maxY - size.height - 8))
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        let chat = JarvisOverlayPanel(contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        chat.title = "EIDIS / 일상 채팅"
        chat.titlebarAppearsTransparent = true
        chat.titleVisibility = .hidden
        chat.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.042, blue: 0.055, alpha: 1)
        chat.isOpaque = true
        chat.hasShadow = true
        chat.hidesOnDeactivate = false
        chat.isReleasedWhenClosed = false
        chat.minSize = NSSize(width: 360, height: 390)
        chat.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        chat.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        chat.contentView = NSHostingView(rootView: JarvisDetachedCasualChatView(dialogue: miniDialogue))
        detachedChatPanel = chat
        detachedChatCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: chat, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.detachedChatPanel === chat else { return }
                self.miniDialogue?.setCasualChatMode(false)
            }
        }
        chat.orderFrontRegardless()
        chat.makeKey()
        NSLog("JARVIS: mini casual chat opened beside active gold core")
    }

    private func closeDetachedChat() {
        if let observer = detachedChatCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            detachedChatCloseObserver = nil
        }
        guard let chat = detachedChatPanel else { return }
        detachedChatPanel = nil
        chat.orderOut(nil)
        chat.contentView = nil
        miniDialogue?.textInputFocused = false
        NSLog("JARVIS: mini casual chat closed; mini core remains active")
    }

    /// Two native windows, one visual workspace. Preserve the current dialogue
    /// and the microphone/hotkey lifecycle; only change the overlay geometry.
    private func openChromeWorkspace(_ channel: JarvisSocialProfile, channelID: String?,
                                     dialogue: JarvisOverlayConversation) async -> Bool {
        guard let window = panel, let screen = window.screen ?? NSScreen.main else { return false }
        let visible = screen.visibleFrame
        let width = min(470, max(300, visible.width * 0.27))
        let gap: CGFloat = 8
        let sidebar = NSRect(x: visible.minX, y: visible.minY,
                             width: width, height: visible.height)
        let right = NSRect(x: sidebar.maxX + gap, y: visible.minY,
                           width: visible.maxX - sidebar.maxX - gap, height: visible.height)
        guard right.width >= 440, let primary = NSScreen.screens.first else { return false }
        // Chrome AppleScript bounds use top-down screen coordinates.
        let bounds = CGRect(x: right.minX, y: primary.frame.maxY - right.maxY,
                            width: right.width, height: right.height)
        // Let macOS automation permission prompts appear above the overlay.
        window.level = .normal
        let success = await dialogue.chrome.openWorkspace(channel, youtubeChannelID: channelID,
                                                          chromeBounds: bounds)
        guard self.panel === window, self.dialogue === dialogue else { return false }
        guard success else {
            window.level = chromeFullscreenFrame == nil ? .screenSaver : .floating
            window.orderFrontRegardless()
            return false
        }
        if chromeFullscreenFrame == nil { chromeFullscreenFrame = screen.frame }
        window.setFrame(sidebar, display: true, animate: false)
        window.level = .floating
        window.orderFrontRegardless()
        // Escape belongs to the real Chrome page when Chrome has focus.
        hotkey?.uninstallEscape()
        return true
    }

    private func restoreChromeWorkspaceFrame() {
        guard let panel, let frame = chromeFullscreenFrame else { return }
        chromeFullscreenFrame = nil
        let target = NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.frame
            ?? NSScreen.main?.frame ?? frame
        panel.setFrame(target, display: true, animate: false)
        panel.level = .screenSaver
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        _ = hotkey?.installEscape()
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
        guard chromeFullscreenFrame == nil, let panel, direction != 0,
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
    /// Esc = 한 단계 뒤로: 브라우저 작업 → 작업실(SNS·프로젝트) → 대시보드 → 코어.
    /// 코어 화면에서 누를 때만 자비스 창을 닫는다. (이전에는 어디서 누르든 창 전체가 닫혔다.)
    func escapeOneStep() {
        if let dialogue, dialogue.chromeWorkspaceVisible {
            Task { await dialogue.returnFromChromeWorkspace() }
        } else if let live = dialogue?.liveDashboard, live.snsRoomOpen {
            withAnimation(.easeInOut(duration: 0.28)) { live.snsRoomOpen = false }
        } else if let live = dialogue?.liveDashboard, live.workroomProject != nil {
            withAnimation(.easeInOut(duration: 0.28)) { live.workroomProject = nil }
        } else if let live = dialogue?.liveDashboard, live.isVisible {
            _ = live.hide()
        } else {
            dismiss()
        }
    }

    func dismiss() {
        guard let window = panel else { return }
        closeDetachedChat()
        dialogue?.onCasualChatModeChanged = nil
        chromeFullscreenFrame = nil
        pauseDeka("전체 화면 닫기 · 코어 전환")
        hotkey?.uninstallEscape()
        hotkey?.uninstallMicrophone()
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
        onPresentationChanged?(false)
        if miniEnabled { showMini() } else { stopDeka("코어 닫힘 · 상시 대기 종료") }
    }

    func stop() {
        closeDetachedChat()
        dialogue?.onCasualChatModeChanged = nil
        stopDeka()
        hideMini()
        LocalSpeechListener.beforeCapture = nil
        dekaResumeTask?.cancel()
        dekaResumeTask = nil
        if let dekaSleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(dekaSleepObserver) }
        if let dekaWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(dekaWakeObserver) }
        dekaSleepObserver = nil
        dekaWakeObserver = nil
        hotkey?.uninstallEscape()
        hotkey?.uninstallMicrophone()
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
