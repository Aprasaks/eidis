import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import WebKit

/// Native macOS shell. It does not send screenshots to any AI model or server.
@main
struct EidisMacApp: App {
    @NSApplicationDelegateAdaptor(JarvisAppLifecycle.self) private var lifecycle

    var body: some Scene {
        WindowGroup("JARVIS") {
            JarvisWindow()
                .environmentObject(lifecycle.server)
        }
        .defaultSize(width: 1180, height: 770)
    }
}

@MainActor
final class ScreenObserver: ObservableObject {
    @Published private(set) var preview: NSImage?
    @Published private(set) var status = "화면 캡처가 꺼져 있습니다."
    @Published private(set) var busy = false
    @Published private(set) var recognizedText = ""
    @Published private(set) var recognizedLineCount = 0
    @Published private(set) var questionReply = ""

    func answerQuestion(_ question: String, uiElements: [ScreenUIEvidence] = []) {
        guard !busy else { return }
        questionReply = LocalScreenInsights.answer(
            question: question, recognizedText: recognizedText, uiElements: uiElements
        )
    }

    func clearAnswer() {
        questionReply = ""
    }

    func captureOnce() {
        guard !busy else { return }
        busy = true
        preview = nil
        recognizedText = ""
        recognizedLineCount = 0
        questionReply = ""
        status = "화면 접근 권한을 확인하고 있습니다."
        Task {
            defer { busy = false }
            do {
                // Only one frame on explicit user action, never a background stream.
                let shareable = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                guard let display = shareable.displays.first else {
                    status = "캡처 가능한 디스플레이가 없습니다."
                    return
                }
                // Do not OCR JARVIS's own window; capture the other visible apps.
                let ownApps = shareable.applications.filter {
                    $0.bundleIdentifier == Bundle.main.bundleIdentifier
                }
                let filter = SCContentFilter(display: display,
                                             excludingApplications: ownApps,
                                             exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = display.width
                configuration.height = display.height
                configuration.showsCursor = true
                let frame = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                preview = NSImage(
                    cgImage: frame,
                    size: NSSize(width: CGFloat(frame.width), height: CGFloat(frame.height))
                )
                recognizedText = ""
                recognizedLineCount = 0
                questionReply = ""
                status = "화면 캡처 완료 · Mac에서 글자를 읽고 있습니다."
                do {
                    // Recognition runs off the UI thread. Never stores or uploads the image.
                    let result = try await Task.detached(priority: .userInitiated) {
                        try LocalScreenText.recognize(in: frame)
                    }.value
                    recognizedText = result.text
                    recognizedLineCount = result.lineCount
                    status = result.lineCount > 0
                        ? "로컬 글자 인식 완료 · \(result.lineCount)줄 · 외부 전송 없음."
                        : "캡처 성공 · 인식할 글자를 찾지 못했습니다. 그림이나 도표의 의미는 아직 분석하지 않습니다."
                } catch {
                    status = "화면 캡처 성공 · 로컬 글자 인식 실패: \(error.localizedDescription)"
                }
            } catch {
                preview = nil
                recognizedText = ""
                recognizedLineCount = 0
                questionReply = ""
                status = "화면 확인 실패: \(error.localizedDescription)"
            }
        }
    }

    func clear() {
        preview = nil
        recognizedText = ""
        recognizedLineCount = 0
        questionReply = ""
        status = "캡처 화면과 인식한 글자를 메모리에서 지웠습니다. 파일로 저장하지 않았습니다."
    }
}

private enum JarvisTab: Hashable {
    case assistant, work, speech, screen, ui, diagnostics
}

struct JarvisWindow: View {
    @EnvironmentObject private var localServer: JarvisBundledServer
    @StateObject private var voice = JarvisVoiceService()
    @StateObject private var elevenLabs = ElevenLabsVoiceService()
    @StateObject private var vision = ScreenObserver()
    @StateObject private var uiInspector = AccessibilityInspector()
    @StateObject private var bridge = JarvisBridge()
    @StateObject private var projectWork = ApprovedWorkModel()
    @State private var selectedTab: JarvisTab = .assistant
    @ObservedObject private var summonOverlay = JarvisSummonOverlay.shared
    @State private var workspaceRequest: JarvisWorkspaceCommand?
    @State private var reloadID = UUID()
    @State private var screenQuestion = "이 화면에서 오류가 있는지 찾아줘"
    @State private var showLaunchIntro = true
    @State private var showLegacyConsole = false
    // The immersive first screen can be switched back to the detailed
    // dashboard; persisted locally without modifying project memory.
    @AppStorage("JARVIS_CinematicHome_Enabled") private var cinematicHome = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // On-device numbers are read only from a confirmed /api/projects reply.
    // The local model state is a capability check, not evidence of a completed task.
    private var systemSnapshot: JarvisSystemSnapshot {
        let loaded = localServer.ready && projectWork.lastRefreshSucceeded
        let projects = loaded ? projectWork.projects : []
        let counts = projects.reduce((todo: 0, doing: 0, done: 0, blocked: 0)) {
            previous, project in
            (
                todo: previous.todo + project.taskCounts.todo,
                doing: previous.doing + project.taskCounts.doing,
                done: previous.done + project.taskCounts.done,
                blocked: previous.blocked + project.taskCounts.blocked
            )
        }
        let firstDoing = projects.lazy.compactMap { project -> (String, String)? in
            guard let task = project.nextTasks.first(where: { $0.status == "doing" }) else {
                return nil
            }
            return (project.name, task.title)
        }.first
        let firstToDo = projects.lazy.compactMap { project -> (String, String)? in
            guard let task = project.nextTasks.first(where: { $0.status == "todo" }) else {
                return nil
            }
            return (project.name, task.title)
        }.first
        let next = firstDoing ?? firstToDo
        let server: JarvisSystemSnapshot.ServerState = localServer.ready
            ? .online : ((!localServer.attemptedConnection || localServer.checking)
                         ? .checking : .offline)
        return JarvisSystemSnapshot(
            server: server, recordsLoaded: loaded,
            projectCount: projects.count,
            taskCount: counts.todo + counts.doing + counts.done + counts.blocked,
            doingCount: counts.doing, todoCount: counts.todo,
            doneCount: counts.done, blockedCount: counts.blocked,
            nextTaskTitle: next?.1, nextTaskProject: next?.0,
            voiceOutputAvailable: !voice.voiceID.isEmpty &&
                voice.availableVoices.contains(where: { $0.identifier == voice.voiceID }),
            appleModelState: JarvisLocalPlanning.availabilityDescription()
        )
    }

    private func refreshDashboard() {
        Task {
            if !localServer.ready { await localServer.connectOnLaunch() }
            if localServer.ready { await projectWork.refresh() }
            reloadID = UUID()
        }
    }

    private func answerScreenQuestion() {
        // Only the user's last explicit inspection may contribute UI context.
        let controls = uiInspector.inspected
            ? uiInspector.rows.map { ScreenUIEvidence(role: $0.role, label: $0.label) }
            : []
        vision.answerQuestion(screenQuestion, uiElements: controls)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if selectedTab == .assistant && cinematicHome {
                    JarvisImmersiveHomeView(
                        snapshot: systemSnapshot,
                        onShowDashboard: { cinematicHome = false },
                        onRefresh: { refreshDashboard() },
                        onOpenWork: { selectedTab = .work },
                        onOpenSpeech: { selectedTab = .speech },
                        onOpenScreen: { selectedTab = .screen },
                        onOpenDiagnostics: { selectedTab = .diagnostics }
                    )
                } else {
                HStack(spacing: 12) {
                    Image(systemName: "circle.hexagongrid")
                        .foregroundStyle(Color(red: 0.25, green: 0.82, blue: 0.90))
                    Text("JARVIS")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(2.5)
                    Button("자비스 소환") { summonOverlay.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                    Text("PERSONAL SYSTEM")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if localServer.ready {
                        Circle().fill(.cyan).frame(width: 6, height: 6)
                        Text("LOCAL ONLINE")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.73))
                    } else {
                        Text(localServer.checking ? "CONNECTING" : "OFFLINE")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(Color(red: 0.022, green: 0.035, blue: 0.052))

                Divider().overlay(.white.opacity(0.06))

                TabView(selection: $selectedTab) {
                    VStack(spacing: 0) {
                        if cinematicHome {
                            JarvisImmersiveHomeView(
                                snapshot: systemSnapshot,
                                onShowDashboard: { cinematicHome = false },
                                onRefresh: { refreshDashboard() },
                                onOpenWork: { selectedTab = .work },
                                onOpenSpeech: { selectedTab = .speech },
                                onOpenScreen: { selectedTab = .screen },
                                onOpenDiagnostics: { selectedTab = .diagnostics }
                            )
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Spacer()
                                    Button {
                                        cinematicHome = true
                                        showLegacyConsole = false
                                    } label: {
                                        Label("시네마틱 홈으로 돌아가기",
                                              systemImage: "circle.hexagongrid")
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.cyan)
                                }
                                .padding(.horizontal, 22)
                                .padding(.top, 8)
                                JarvisDashboardHomeView(
                                    snapshot: systemSnapshot,
                                    onOpenWork: { selectedTab = .work },
                                    onOpenSpeech: { selectedTab = .speech },
                                    onOpenScreen: { selectedTab = .screen },
                                    onOpenDiagnostics: { selectedTab = .diagnostics },
                                    onOpenConsole: { showLegacyConsole.toggle() },
                                    onRefresh: { refreshDashboard() },
                                    onPreviewVoice: { voice.preview() }
                                )
                            }
                        }
                        if showLegacyConsole {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("기존 자비스 웹 콘솔 · 127.0.0.1")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(localServer.message)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button("Mac 목소리 미리 듣기") { voice.preview() }
                                    Button("콘솔 새로고침") { reloadID = UUID() }
                                    Button("닫기") { showLegacyConsole = false }
                                }
                                LocalDashboard(event: bridge.event)
                                    .id(reloadID)
                                    .frame(minHeight: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                            }
                            .padding(18)
                        }
                    }
                    .tabItem { Label("자비스", systemImage: "circle.hexagongrid") }
                    .tag(JarvisTab.assistant)

                ApprovedProjectsPanel(work: projectWork, requestedWorkspace: workspaceRequest)
                    .tabItem { Label("작업", systemImage: "checklist") }
                    .tag(JarvisTab.work)

                NativeSpeechPanel(
                    bridge: bridge, voice: voice, elevenLabs: elevenLabs,
                    projectWork: projectWork,
                    onWorkspaceRequest: { request in
                        workspaceRequest = request
                        selectedTab = .work
                    }
                )
                    .tabItem { Label("음성", systemImage: "mic") }
                    .tag(JarvisTab.speech)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("자비스의 눈 · 수동 캡처 테스트")
                                .font(.headline)
                            Text("버튼을 누른 경우에만 화면을 한 번 캡처하고 글자를 Mac에서 읽습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("화면 캡처 + 글자 읽기") { vision.captureOnce() }
                            .disabled(vision.busy)
                        Button("지우기") { vision.clear() }
                            .disabled(vision.busy || vision.preview == nil)
                    }
                    Group {
                        if let preview = vision.preview {
                            Image(nsImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 240)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "display")
                                    .font(.system(size: 44, weight: .ultraLight))
                                Text("캡처된 화면 없음")
                                    .font(.title3)
                                Text("스크린샷은 자동으로 저장하거나 AI에 전송하지 않습니다.")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: 240)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 230)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("로컬 글자 인식 (한국어·영어)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if !vision.recognizedText.isEmpty {
                                Text("\(vision.recognizedLineCount)줄")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button("글자 복사") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(vision.recognizedText, forType: .string)
                            }
                            .disabled(vision.recognizedText.isEmpty || vision.busy)
                        }
                        ScrollView {
                            Text(vision.recognizedText.isEmpty
                                 ? "화면 캡처 후 인식한 글자가 여기에 표시됩니다. 이 기능은 그림이나 화면 전체의 의미를 이해하지 않습니다."
                                 : vision.recognizedText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(vision.recognizedText.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 140)
                        .padding(10)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Text("선택한 앱의 버튼·탭 구조 읽기 (별도 권한)")
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            Picker("앱", selection: $uiInspector.selectedPID) {
                                if uiInspector.targets.isEmpty {
                                    Text("실행 중인 앱 없음").tag(pid_t(0))
                                }
                                ForEach(uiInspector.targets) { target in
                                    Text(target.displayName).tag(target.pid)
                                }
                            }
                            .frame(maxWidth: 320)
                            Button("앱 목록 갱신") {
                                uiInspector.refreshTargets()
                                vision.clearAnswer()
                            }
                            Button("접근성 권한 요청") { uiInspector.askForPermission() }
                        }
                        HStack(spacing: 8) {
                            Button("선택 앱 UI 구조 읽기") {
                                uiInspector.inspectSelected()
                                vision.clearAnswer()
                            }
                            .disabled(uiInspector.selectedPID == 0 || vision.busy)
                            Button("UI 기록 지우기") {
                                uiInspector.clear()
                                vision.clearAnswer()
                            }
                            .disabled(!uiInspector.inspected)
                            if uiInspector.inspected {
                                Text("UI 요소 \(uiInspector.rows.count)개")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(uiInspector.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("UI 구조는 직접 선택한 앱만 읽습니다. 화면 OCR은 전체 디스플레이이며, 같은 창이라는 보장은 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .onChange(of: uiInspector.selectedPID) { _, _ in vision.clearAnswer() }
                    .onChange(of: uiInspector.inspected) { _, _ in vision.clearAnswer() }
                    VStack(alignment: .leading, spacing: 9) {
                        Text("화면 글자에 질문하기 · 로컬 분석")
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            TextField("예: 이 화면에서 오류가 뭐야?", text: $screenQuestion)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { answerScreenQuestion() }
                            Button("로컬 답변") { answerScreenQuestion() }
                                .disabled((vision.recognizedText.isEmpty && !uiInspector.inspected) || vision.busy ||
                                          screenQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("음성으로 듣기") { voice.speak(vision.questionReply) }
                                .disabled(vision.questionReply.isEmpty)
                        }
                        ScrollView {
                            Text(vision.questionReply.isEmpty
                                 ? "인식한 글자를 바탕으로 오류 후보나 관련 문구를 찾아줘요. 화면의 이미지 의미나 원인 진단은 아직 할 수 없어요."
                                 : vision.questionReply)
                                .font(.system(size: 12))
                                .foregroundStyle(vision.questionReply.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 105)
                        .padding(10)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    }
                    Text(vision.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }
                    .padding(18)
                }
                .tabItem { Label("화면", systemImage: "eye") }
                .tag(JarvisTab.screen)

                AccessibilityPanel(inspector: uiInspector)
                    .tabItem { Label("UI 구조", systemImage: "rectangle.on.rectangle") }
                    .tag(JarvisTab.ui)
                MacReadinessPanel()
                    .tabItem { Label("진단", systemImage: "stethoscope") }
                    .tag(JarvisTab.diagnostics)
            }
                .padding(.horizontal, 8)
                }
            }
            .background(Color(red: 0.012, green: 0.018, blue: 0.027))
            .preferredColorScheme(.dark)

            if showLaunchIntro {
                JarvisIntroSplashView(snapshot: systemSnapshot)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .task {
            // Intro is a short visual reveal, not a simulated system check.
            // If the server is unavailable the offline dashboard remains usable.
            try? await Task.sleep(for: .milliseconds(2300))
            if !Task.isCancelled {
                if reduceMotion {
                    showLaunchIntro = false
                } else {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        showLaunchIntro = false
                    }
                }
            }
        }
        .onChange(of: localServer.ready) { _, didConnect in
            if didConnect {
                reloadID = UUID()
                Task { await projectWork.refresh() }
            }
        }
        .task {
            if localServer.ready && !projectWork.lastRefreshSucceeded {
                await projectWork.refresh()
            }
        }
    }
}

/// Embeds localhost only, with a bridge for verified native-command replies.
struct LocalDashboard: NSViewRepresentable {
    let event: JarvisVisualEvent?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: URL(string: "http://127.0.0.1:8765")!))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.event = event
        context.coordinator.deliver(to: view)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var event: JarvisVisualEvent?
        private var lastDelivered: UUID?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastDelivered = nil
            deliver(to: webView)
        }

        func deliver(to view: WKWebView) {
            guard !view.isLoading, let event, lastDelivered != event.id else { return }
            guard let data = try? JSONEncoder().encode(event.reply),
                  let json = String(data: data, encoding: .utf8) else { return }
            view.evaluateJavaScript("window.jarvisNativeResult(\(json));") { [weak self] _, error in
                if error == nil { self?.lastDelivered = event.id }
            }
        }
    }
}
