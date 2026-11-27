import SwiftUI

/// Full-screen, TV-friendly JARVIS command center. The active AVPlayer is owned
/// by the parent overlay and moves to the center. This view NEVER renders
/// fake analytics; all values come from live local APIs or bounded git scans.
struct JarvisCommandCenterView: View {
    @ObservedObject var model: JarvisLiveDashboard
    @ObservedObject var dialogue: JarvisOverlayConversation
    @ObservedObject var agentBay: JarvisAgentTerminalBay
    let close: () -> Void
    @State private var selectedAgent: JarvisAgentID = .codex
    @State private var agentPrompt = ""
    @State private var workroomTypedCommand = ""
    @FocusState private var workroomInputFocused: Bool
    @State private var workspaceRevealed = false
    @StateObject private var telemetry = JarvisMacSampler()
    @ObservedObject private var sitePulse = JarvisSitePulse.shared
    /// SNS 작업실 열림 상태는 모델(JarvisLiveDashboard.snsRoomOpen)에 둔다.
    /// Esc 한 단계 뒤로 가기와 코어 버튼이 이 상태를 함께 본다.
    private var showChannelOverview: Bool {
        get { model.snsRoomOpen }
        nonmutating set { model.snsRoomOpen = newValue }
    }

    private let amber = Color(red: 0.94, green: 0.67, blue: 0.30)
    private let muted = Color(red: 0.64, green: 0.66, blue: 0.68)
    private let mint = Color(red: 0.46, green: 0.84, blue: 0.69)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            // The workroom opens directly into actual operations. No
            // branded page header, generic KPI strip, or static project cards.
            let outer = min(32, max(12, width * 0.015))
            let topInset: CGFloat = 10
            let bottomInset: CGFloat = 14
            let closeReserve: CGFloat = 28
            let usableHeight = max(0, height - topInset - bottomInset)
            let scale = min(2.0, max(0.84, min(width / 1430, height / 880)))
            let narrow = width < 1120
            let gap: CGFloat = narrow ? 10 : 16
            let innerWidth = max(0, width - 2 * outer)
            let columnHeight = max(0, usableHeight - closeReserve)
            let centerWidth = JarvisOverviewGeometry.centerWidth(innerWidth: innerWidth, height: height)
            let leftWidth = max(0, (innerWidth - centerWidth - 2 * gap) * 0.5)
            let rightWidth = max(0, innerWidth - centerWidth - 2 * gap - leftWidth)

            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    // 대시보드 닫기(코어로). 작업실이 열려 있으면 작업실의 "관제실 복귀"만 보이도록 숨긴다.
                    // 이전에는 8×8px로 거의 보이지 않았고, 작업실 위에서 닫기 버튼이 두 개로 보였다.
                    if model.workroomProject == nil && !showChannelOverview {
                        Button(action: close) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                                Text("코어로 · esc").font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 26)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.22)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.88))
                        .help("대시보드를 닫고 코어 화면으로 (Esc)")
                        .accessibilityLabel("대시보드 닫기")
                        .accessibilityIdentifier("jarvis-command-center-close")
                    }
                }
                .frame(height: closeReserve)
                HStack(alignment: .top, spacing: gap) {
                    leftColumn(height: columnHeight, scale: scale, compact: narrow)
                        .frame(width: leftWidth, height: columnHeight)
                        .offset(x: workspaceRevealed ? 0 : -26)
                        .opacity(workspaceRevealed ? 1 : 0)
                    centerColumn(height: columnHeight, scale: scale)
                        .frame(width: centerWidth, height: columnHeight)
                    rightColumn(height: columnHeight, scale: scale)
                        .frame(width: rightWidth, height: columnHeight)
                        .offset(x: workspaceRevealed ? 0 : 26)
                        .opacity(workspaceRevealed ? 1 : 0)
                }
                .frame(height: columnHeight)
            }
            .frame(width: innerWidth, height: usableHeight, alignment: .top)
            .padding(.horizontal, outer)
            .padding(.top, topInset)
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .accessibilityIdentifier("jarvis-command-center")
            .allowsHitTesting(model.workroomProject == nil && !showChannelOverview)
            // 작업실이 열리면 뒤 대시보드 버튼을 접근성 트리에서도 숨긴다.
            // (자동 클릭·음성 제어가 보이지 않는 뒤쪽 버튼을 누르는 문제 방지)
            .accessibilityHidden(model.workroomProject != nil || showChannelOverview)
            .overlay {
                if showChannelOverview {
                    // SNS / YouTube workroom: same full-size layer as project workrooms.
                    JarvisChannelMonitorView(model: model, dialogue: dialogue, agentBay: agentBay) {
                        withAnimation(.easeInOut(duration: 0.28)) { showChannelOverview = false }
                    }
                    .padding(outer)
                    .frame(width: width, height: height)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(21)
                } else if let project = model.workroomProject {
                    JarvisProjectWorkspace(project: project, agentBay: agentBay) {
                        withAnimation(.easeInOut(duration: 0.28)) { model.workroomProject = nil }
                    }
                    .padding(outer)
                    .frame(width: width, height: height)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(20)
                }
            }
        }
        .onAppear {
            // Opening this explicit conversation surface starts live dictation.
            // The normal local Jarvis wake listener yields its mic while
            // Apple's speech recognizer owns the input.
            dialogue.setDashboardDictation(true)
            agentBay.probeAll()
            sitePulse.start()   // 왼쪽 사이트 카드 실제 상태 (15분마다)
            withAnimation(.easeOut(duration: 0.72)) { workspaceRevealed = true }
        }
        .onDisappear {
            dialogue.setDashboardDictation(false)
            workspaceRevealed = false
        }
        .task {
            telemetry.reset()
            while !Task.isCancelled {
                telemetry.sample()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .task {
            // Use wall-clock KST. Work itself lives in the agent bay rather
            // than this view, so closing the detail panel does not cancel it.
            while !Task.isCancelled {
                // SNS connection sheets now live inside the channel monitor sheet.
                if !showChannelOverview {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        _ = model.openKnowledgeAtMidnightIfDue()
                    }
                    // Only navigation here; the app-lifetime scheduler owns execution.
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onChange(of: agentBay.nightShiftFinishedDay) { _, day in
            if day != nil && model.workroomProject == .dev {
                withAnimation(.easeInOut(duration: 0.28)) { model.workroomProject = nil }
            }
        }
    }

    private func leftColumn(height: CGFloat, scale: CGFloat, compact: Bool) -> some View {
        let spacing: CGFloat = 11
        let cardHeight = max(55, (height - 42 - spacing * 4) / 4)
        return VStack(spacing: spacing) {
            ForEach(JarvisWorkroomProject.allCases) { project in
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) { model.workroomProject = project }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: project.symbol)
                                .font(.system(size: 21 * scale, weight: .light))
                                .foregroundStyle(project.accent)
                                .frame(width: 42 * scale, height: 42 * scale)
                                .background(project.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.title)
                                    .font(.system(size: 15 * scale, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(project.accent)
                                Text(project.domain)
                                    .font(.system(size: 10 * scale, design: .monospaced))
                                    .foregroundStyle(muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(project.accent.opacity(0.85))
                        }
                        Rectangle().fill(project.accent.opacity(0.20)).frame(height: 1)
                        if project == .dev {
                            HStack {
                                Text("KNOWLEDGE")
                                    .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                                Spacer()
                                Text(agentBay.knowledgePilot == nil ? "시범 실행 준비" : agentBay.knowledgePilotLabel)
                                    .font(.system(size: 10 * scale))
                            }
                            .foregroundStyle(project.accent)
                            Text("00:00–01:00 KST  /  검토 등록 목표 3편")
                                .font(.system(size: 10 * scale, design: .monospaced))
                                .foregroundStyle(muted)
                            Text("오늘 검토 등록 \(agentBay.knowledgeDailyStaged)편 · " +
                                 (JarvisKnowledgeDailyBudget.usesSeparateRepairs()
                                  ? "신규 \(agentBay.knowledgeDailyStarts)/3 · 복구 \(agentBay.knowledgeDailyRepairs)/3"
                                  : "기존 실행 \(agentBay.knowledgeDailyStarts)/3"))
                                .font(.system(size: 11 * scale, weight: .medium))
                                .foregroundStyle(project.accent)
                        } else if let pulse = sitePulse.pulses[project] {
                            // 실제 상태 (JarvisSitePulse): 사이트별 한 줄 + 최근 커밋
                            if let detail = pulse.detail {
                                Text(detail)
                                    .font(.system(size: 12 * scale, weight: .medium))
                                    .foregroundStyle(pulse.detailWarning ? Color.orange : project.accent)
                                    .lineLimit(1)
                            }
                            if let note = pulse.note {
                                Text(note)
                                    .font(.system(size: 11 * scale))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(1)
                            }
                            if let commit = pulse.commitLabel {
                                Label(commit, systemImage: "arrow.triangle.branch")
                                    .font(.system(size: 11 * scale))
                                    .foregroundStyle(muted)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("사이트 상태 확인 중…")
                                .font(.system(size: 12 * scale))
                                .foregroundStyle(muted)
                        }
                        Spacer(minLength: 0)
                        if let pulse = sitePulse.pulses[project] {
                            // 카드 하단: 사이트 응답 상태 (초록 = 정상)
                            HStack(spacing: 6) {
                                Circle().fill(pulse.siteOK == true ? mint : (pulse.siteOK == false ? Color.orange : muted))
                                    .frame(width: 7, height: 7)
                                Text("사이트 " + pulse.siteLabel)
                                Spacer(minLength: 0)
                                if let at = pulse.checkedAt {
                                    Text(at.formatted(date: .omitted, time: .shortened) + " 확인")
                                }
                            }
                            .font(.system(size: 10 * scale, design: .monospaced))
                            .foregroundStyle(muted)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(LinearGradient(colors: [project.accent.opacity(0.09), .black.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(project.accent.opacity(0.48), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(height: cardHeight)
                .accessibilityIdentifier("jarvis-project-" + project.rawValue)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.28)) { showChannelOverview = true }
            } label: {
                // Live API values only; unknown stays "—". 아직 첫 조회 전이면 "…"(확인 중)로 구분한다.
                let instagram = model.instagramSnapshot == nil ? "…"
                    : (model.instagramSnapshot?.followersCount.map { String($0) } ?? "—")
                let youtube = model.youtubeSummary == nil ? "…"
                    : ((model.youtubeSummary?.connected == true ? model.youtubeSummary?.data?.subscriberCount : nil) ?? "—")
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                    Text("SNS / YOUTUBE").fontWeight(.semibold)
                    Text("IG \(instagram) · YT \(youtube)")
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer()
                    Text("CLAUDE CODE")
                        .font(.system(size: 9 * scale, weight: .medium, design: .monospaced))
                        .foregroundStyle(JarvisAgentID.claude.workroomAccent)
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11 * scale, design: .monospaced))
                .foregroundStyle(amber)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(amber.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("jarvis-channel-overview")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private func centerColumn(height: CGFloat, scale: CGFloat) -> some View {
        // The continuous gold AVPlayer stays behind this transparent lane.
        // Real recognized speech and the Qwen response become the holographic
        // communication overlay; no simulated agent text or second core.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(dialogue.isListening ? mint : amber)
                        .symbolEffect(.variableColor.iterative, options: .repeating,
                                      isActive: dialogue.isListening)
                    Text("JARVIS / VOICE LINK")
                        .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(amber)
                    Spacer(minLength: 0)
                    Text(dialogue.isListening ? "LISTENING" :
                         dialogue.isThinking ? "PROCESSING" :
                         dialogue.isSpeaking ? "SPEAKING" : "READY")
                        .font(.system(size: 9 * scale, design: .monospaced))
                        .foregroundStyle(dialogue.isListening ? mint : muted)
                }
                Rectangle().fill(amber.opacity(0.27)).frame(height: 1)
                if !dialogue.liveTranscript.isEmpty {
                    Text(dialogue.liveTranscript)
                        .font(.system(size: 14 * scale, weight: .medium))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("jarvis-workroom-live-transcript")
                } else if let turn = dialogue.dialogueTurns.last(where: { $0.role == "YOU" }) {
                    Text(turn.content)
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.white.opacity(0.77))
                        .accessibilityIdentifier("jarvis-workroom-last-command")
                } else {
                    Text(dialogue.isListening ? "듣고 있습니다…" : "코어를 누르면 기본 화면으로 돌아갑니다")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(muted)
                }
                if dialogue.isThinking && !dialogue.streamingAnswer.isEmpty {
                    Text(dialogue.streamingAnswer)
                        .foregroundStyle(mint)
                        .accessibilityIdentifier("jarvis-workroom-streaming-answer")
                } else if let answer = dialogue.dialogueTurns.last(where: { $0.role == "DECHIVE" }) {
                    Text(answer.content)
                        .foregroundStyle(.white.opacity(0.86))
                } else if !dialogue.status.isEmpty {
                    Text(dialogue.status)
                        .foregroundStyle(muted)
                }
            }
            .font(.system(size: 12 * scale))
            .lineLimit(3)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.black.opacity(0.29), Color.black.opacity(0.76)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(alignment: .leading) {
                Rectangle().fill(amber.opacity(0.54)).frame(width: 2)
                    .padding(.vertical, 14)
            }
            .accessibilityIdentifier("jarvis-workroom-center-conversation")
            HStack(spacing: 7) {
                Button {
                    dialogue.setDashboardDictation(!dialogue.dashboardDictationEnabled)
                } label: {
                    Image(systemName: dialogue.dashboardDictationEnabled ? "mic.fill" : "mic.slash")
                        .foregroundStyle(dialogue.isListening ? mint : amber)
                }
                .buttonStyle(.plain)
                .help("마이크 켜기 / 일시정지")
                .accessibilityIdentifier("jarvis-workroom-microphone")
                TextField("명령 또는 대화", text: $workroomTypedCommand)
                    .textFieldStyle(.roundedBorder)
                    .focused($workroomInputFocused)
                    .onChange(of: workroomInputFocused) { _, active in
                        dialogue.textInputFocused = active
                    }
                    .onSubmit { submitWorkroomCommand() }
                    .disabled(dialogue.isListening)
                    .accessibilityIdentifier("jarvis-workroom-command-input")
                Button("전송") { submitWorkroomCommand() }
                    .buttonStyle(.plain)
                    .foregroundStyle(amber)
                    .disabled(workroomTypedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              dialogue.isListening)
                    .accessibilityIdentifier("jarvis-workroom-command-send")
            }
            .font(.system(size: 10 * scale))
            .padding(9)
            .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(amber.opacity(0.24)))
        }
        .frame(height: height)
        .accessibilityIdentifier("jarvis-workroom-center-lane")
    }

    private func submitWorkroomCommand() {
        let message = workroomTypedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !dialogue.isListening else { return }
        workroomTypedCommand = ""
        dialogue.submitTyped(message)
    }

    private func rightColumn(height: CGFloat, scale: CGFloat) -> some View {
        // The three real worker terminals get equal, usable display areas.
        // Health polling is kept in a small summary, not a fabricated stream.
        let spacing: CGFloat = 9
        let controlHeight: CGFloat = min(116, height * 0.15)
        let eventHeight: CGFloat = min(124, height * 0.16)
        let laneHeight = max(25, (height - controlHeight - eventHeight - spacing * 4) / 3)
        let laneHeights = Array(repeating: laneHeight, count: JarvisAgentID.allCases.count)
        return VStack(spacing: spacing) {
            ForEach(Array(JarvisAgentID.allCases.enumerated()), id: \.element.id) { index, id in
                agentTerminalCard(id, scale: scale)
                    .frame(height: laneHeights[index])
            }
            agentEventStream(scale: scale).frame(height: eventHeight)
            agentLaunchControl(scale: scale).frame(height: controlHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .accessibilityIdentifier("jarvis-agent-terminal-bay")
    }

    private func agentTerminalCard(_ id: JarvisAgentID, scale: CGFloat) -> some View {
        let lane = agentBay.lane(id)
        let accent = id.workroomAccent
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Circle()
                    .fill(lane.state == .running ? mint :
                          lane.state == .missing || lane.state == .failed ? Color.orange : accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: lane.state == .running ? mint.opacity(0.5) : accent.opacity(0.42), radius: 5)
                Text(id.title.uppercased())
                    .font(.system(size: 14 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                Text(lane.stateLabel)
                    .font(.system(size: 10 * scale, design: .monospaced))
                    .foregroundStyle(lane.state == .running ? mint : muted)
                if lane.state == .running {
                    Button("중단") { agentBay.cancel(id) }
                        .font(.system(size: 9 * scale))
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                }
            }
            Rectangle().fill(accent.opacity(0.26)).frame(height: 1)
            if lane.logs.isEmpty {
                Text(lane.state == .ready ? "실행 중인 작업 없음" :
                     lane.state == .missing ? "CLI 실행 파일 없음" :
                     lane.state == .checking ? "로컬 실행 파일 확인 중" :
                     "아직 실행 출력 없음")
                    .font(.system(size: 12 * scale, design: .monospaced))   // 10 → 12
                    .foregroundStyle(muted)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(lane.logs.enumerated()), id: \.offset) { i, line in
                                Text(line)
                                    .font(.system(size: 11 * scale, design: .monospaced))   // 10 → 11
                                    .foregroundStyle(.white.opacity(0.85))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                        }
                    }
                    .onChange(of: lane.logs.count) { _, _ in
                        if let last = lane.logs.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.10),
                         Color.black.opacity(0.60)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent.opacity(0.68), lineWidth: 1.1))
        .accessibilityIdentifier("jarvis-agent-terminal-\(id.rawValue)")
    }

    private func agentLaunchControl(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text("AGENT CONTROL / 읽기 전용")
                    .foregroundStyle(amber)
                Spacer(minLength: 0)
                Button("연결 확인") { agentBay.probeAll(force: true) }
                    .buttonStyle(.plain)
                    .foregroundStyle(mint)
                    .accessibilityIdentifier("jarvis-agent-probe")
            }
            .font(.system(size: 11 * scale, weight: .semibold, design: .monospaced))   // 10 → 11
            HStack(spacing: 6) {
                Picker("작업자", selection: $selectedAgent) {
                    ForEach(JarvisAgentID.allCases) { id in
                        Text(id.title).tag(id)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 130)
                Button("분석 시작") {
                    agentBay.runReadOnly(selectedAgent, prompt: agentPrompt)
                }
                .disabled(agentPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          agentBay.isAnyRunning ||
                          [.missing, .checking].contains(agentBay.lane(selectedAgent).state))
                .buttonStyle(.borderedProminent)   // 비활성 회색 글자만 보이던 버튼을 눈에 띄게
                .tint(amber.opacity(0.8))
                .controlSize(.small)
                .font(.system(size: 11 * scale, weight: .semibold))
                .accessibilityIdentifier("jarvis-agent-start-readonly")
            }
            TextField("읽기 전용 분석 요청을 입력하세요", text: $agentPrompt)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12 * scale))   // 10 → 12
                .accessibilityIdentifier("jarvis-agent-task-prompt")
            Text("사용자 요청 시 실행 · 읽기 전용 · 수정/발행 차단")
                .font(.system(size: 10 * scale))   // 9 → 10
                .foregroundStyle(muted)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.035, green: 0.042, blue: 0.048),
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(amber.opacity(0.22)))
    }

    private func agentEventStream(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "waveform.path").foregroundStyle(amber)
                Text("LIVE / OPERATIONS").foregroundStyle(amber)
                Spacer()
                if let sample = telemetry.current, let cpu = sample.cpuPercent {
                    Text(String(format: "CPU %.0f%%", cpu)).foregroundStyle(muted)
                }
            }
            .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
            Rectangle().fill(amber.opacity(0.24)).frame(height: 1)
            if let entry = agentBay.events.last {
                Text(entry).font(.system(size: 10 * scale, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86)).lineLimit(2)
            } else {
                Text("현재 AI 작업 실행 없음").font(.system(size: 10 * scale)).foregroundStyle(muted)
            }
            let checks = model.sourceChecks
            let failures = checks.filter { !$0.success }
            HStack(spacing: 8) {
                Text("HEALTH").foregroundStyle(muted)
                Text(checks.isEmpty ? "확인 중" : "\(checks.count - failures.count)/\(checks.count) OK")
                    .foregroundStyle(failures.isEmpty ? mint : .orange)
                if let check = checks.first {
                    Text(check.at.formatted(date: .omitted, time: .shortened)).foregroundStyle(muted)
                    Spacer(minLength: 0)
                    Text(failures.isEmpty ? check.source : failures.map(\.source).joined(separator: " · "))
                        .foregroundStyle(failures.isEmpty ? muted : .orange)
                        .lineLimit(1)
                        .help(failures.map { $0.source + ": " + $0.detail }.joined(separator: "\n"))
                }
            }
            .font(.system(size: 9 * scale, design: .monospaced))
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(amber.opacity(0.28), lineWidth: 0.8))
    }

    private func macTelemetryCard(scale: CGFloat) -> some View {
        panel("MAC / SYSTEM TELEMETRY", symbol: "cpu", scale: scale) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 9) {
                    if let sample = telemetry.current {
                        usageRow("CPU 전체", value: sample.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "측정 중",
                                 fraction: sample.cpuPercent.map { $0 / 100 }, scale: scale)
                        usageRow("메모리 · VM 추정", value: sample.memoryBytes.map { gib($0) + " / " + gib(sample.totalMemory) } ?? "미확인",
                                 fraction: sample.memoryBytes.map { Double($0) / Double(max(1,sample.totalMemory)) }, scale: scale)
                        let available = sample.diskAvailable
                        usageRow("저장소 · 데이터 볼륨", value: available.map { gib($0) + " 여유" } ?? "미확인",
                                 fraction: sample.diskUsed.flatMap { used in available.map { Double(used) / max(1, Double(used) + Double($0)) } }, scale: scale)
                        if let used = sample.diskUsed, let total = sample.diskTotal {
                            systemRow("볼륨 사용 / 용량", gib(used) + " / " + gib(total), scale: scale)
                        }
                        systemRow("배터리", sample.batteryPercent.map { "\($0)%" } ?? "미확인", scale: scale)
                        systemRow("전원", sample.powerSource, scale: scale)
                        systemRow("열 상태", sample.thermal, scale: scale)
                        Text("Mac OS 카운터 · 3초 간격")
                            .font(.system(size: 9 * scale)).foregroundStyle(muted)
                    } else { status("Mac 시스템 값 측정 중", scale: scale) }
                }
            }.scrollIndicators(.visible)
        }
    }
    private func gib(_ bytes: UInt64) -> String {
        String(format: "%.1f GiB", Double(bytes) / 1_073_741_824)
    }
    private func usageRow(_ name: String, value: String, fraction: Double?, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            systemRow(name, value, scale: scale)
            if let fraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule().fill(fraction > 0.9 ? amber : mint)
                            .frame(width: geometry.size.width * min(1, max(0,fraction)))
                    }
                }.frame(height: 5)
            }
        }
    }

    private func panel<Content: View>(_ title: String, symbol: String, scale: CGFloat,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(amber)
            Rectangle().fill(amber.opacity(0.22)).frame(height: 1)
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.085, green: 0.068, blue: 0.042).opacity(0.71),
                         Color.black.opacity(0.60)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            LinearGradient(colors: [amber.opacity(0.44), amber.opacity(0.12), amber.opacity(0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9))
        .clipped()
    }

    private func projectsCard(scale: CGFloat) -> some View {
        panel("PROJECT OPERATIONS / 로컬 작업 원장", symbol: "square.stack.3d.up", scale: scale) {
            if !model.projectsReady {
                status("프로젝트 원장 연결 실패 또는 조회 중", scale: scale)
            } else {
                HStack(spacing: 8) {
                    labelValue("진행", String(model.doing), scale: scale)
                    labelValue("예정", String(model.todo), scale: scale)
                    labelValue("완료", String(model.done), scale: scale)
                    labelValue("막힘", String(model.blocked), scale: scale)
                }
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.projects) { project in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(project.name == "JARVIS eidis" ? "DECHIVE / CORE" : project.name)
                                        .font(.system(size: 12 * scale, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(project.taskCounts.done)/\(project.tasks.count)")
                                        .font(.system(size: 10 * scale, design: .monospaced))
                                        .foregroundStyle(muted)
                                }
                                progress(project.taskCounts.done, total: project.tasks.count)
                                if let next = project.nextTasks.first {
                                    Text("NEXT / \(next.title)")
                                        .font(.system(size: 10 * scale))
                                        .foregroundStyle(muted)
                                        .lineLimit(2)
                                }
                            }
                        }
                        if model.projects.isEmpty {
                            status("등록된 프로젝트 없음", scale: scale)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.visible)
            }
        }
    }

    private func gitCard(scale: CGFloat) -> some View {
        panel("GITHUB + LOCAL GIT / 전체 저장소", symbol: "chevron.left.forwardslash.chevron.right", scale: scale) {
            if let snapshot = model.gitSnapshot {
                Text("범위: \(snapshot.scannedLocations.joined(separator: ", ")) 하위 일부 폴더")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(muted)
                    .lineLimit(2)
                if snapshot.truncated {
                    Text("탐색 상한에 도달함 · 전체 목록 아님")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(amber)
                }
                if let error = snapshot.error { status(error, scale: scale) }
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 9) {
                        if let remote = model.githubSnapshot {
                            if let error = remote.error {
                                status("GitHub: " + error, scale: scale)
                            } else {
                                HStack(spacing: 6) {
                                    Text("REMOTE / GitHub API · \(remote.repositories.count)개")
                                        .foregroundStyle(mint)
                                    Spacer(minLength: 0)
                                    Text(remote.checkedAt.formatted(date: .omitted, time: .shortened))
                                        .foregroundStyle(muted)
                                }
                                .font(.system(size: 10 * scale, design: .monospaced))
                                if remote.truncated {
                                    status("표시 상한 100개 · 전체 목록 아님", scale: scale)
                                }
                                ForEach(remote.repositories) { item in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(item.fullName).foregroundStyle(.white)
                                                .lineLimit(1)
                                            Spacer(minLength: 3)
                                            Text(item.privateRepo ? "PRIVATE" : "PUBLIC")
                                                .foregroundStyle(amber)
                                        }
                                        .font(.system(size: 10 * scale, design: .monospaced))
                                        Text("기본 \(item.defaultBranch ?? "미확인") · 열린 이슈/PR \(item.openIssueOrPrCount.map(String.init) ?? "—")")
                                            .font(.system(size: 9 * scale))
                                            .foregroundStyle(muted)
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        } else {
                            status(model.githubIsLoading ? "GitHub API에서 원격 저장소를 조회 중…" : "GitHub 원격 조회 준비 중", scale: scale)
                        }
                        Rectangle().fill(amber.opacity(0.2)).frame(height: 1)
                        Text("LOCAL / 이 Mac의 Git 작업복사본")
                            .font(.system(size: 10 * scale, design: .monospaced))
                            .foregroundStyle(mint)
                        ForEach(snapshot.repositories) { repo in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(repo.name)
                                        .font(.system(size: 12 * scale, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 5)
                                    Text(repo.branch)
                                        .font(.system(size: 10 * scale, design: .monospaced))
                                        .foregroundStyle(amber)
                                        .lineLimit(1)
                                }
                                Text(repo.latestCommit)
                                    .font(.system(size: 10 * scale, design: .monospaced))
                                    .foregroundStyle(muted)
                                    .lineLimit(1)
                                Text(repo.trackedChanged.map { "추적 파일 변경 \($0)개" } ?? "변경 사항 확인 불가")
                                    .font(.system(size: 9 * scale))
                                    .foregroundStyle(mint.opacity(0.85))
                            }
                            .padding(.vertical, 3)
                        }
                        if snapshot.repositories.isEmpty { status("발견한 로컬 Git 저장소 없음", scale: scale) }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.visible)
                Text("GitHub는 로그인 계정의 API 결과, 로컬 Git은 Mac 작업복사본입니다.")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(muted)
                    .lineLimit(2)
            } else {
                status(model.gitIsLoading ? "로컬 Git 저장소를 읽는 중…" : "로컬 Git 조회 준비 중", scale: scale)
            }
        }
    }

    private func knowledgeCard(scale: CGFloat) -> some View {
        panel("KNOWLEDGE / 자료·기억", symbol: "books.vertical", scale: scale) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    if let count = model.vaultTotal {
                        labelValue("활성 자료", "\(count)", scale: scale)
                        ForEach(JarvisKnowledgeVault.categoryOrder, id: \.self) { category in
                            if let total = model.vaultCounts[category], total > 0 {
                                HStack {
                                    Text(JarvisKnowledgeVault.labels[category] ?? category)
                                    Spacer()
                                    Text("\(total)")
                                }
                                .font(.system(size: 10 * scale))
                                .foregroundStyle(muted)
                            }
                        }
                        if count == 0 { status("활성 보관함이 비어 있습니다.", scale: scale) }
                    } else { status("자료 보관함 조회 안 됨", scale: scale) }
                    Divider().overlay(muted.opacity(0.25))
                    JarvisLearningReviewView(learning: dialogue.learning)
                    Text("로컬 SQLite · 외부 동기화 아님")
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.visible)
        }
    }

    private func systemCard(scale: CGFloat) -> some View {
        panel("SYSTEM / 상태", symbol: "waveform.path.ecg", scale: scale) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    systemRow("SQLite", model.databaseStatus == "ok" ? "OK" : "확인 불가", scale: scale)
                    systemRow("Ollama", model.ollamaVersion.map { "v\($0)" } ?? "연결 안 됨", scale: scale)
                    systemRow("프로필", model.profileCount.map { "\($0)건" } ?? "확인 불가", scale: scale)
                    systemRow("저장 자료", model.vaultTotal.map { "\($0)건" } ?? "미확인", scale: scale)
                    ForEach(JarvisKnowledgeVault.categoryOrder, id: \.self) { category in
                        if let count = model.vaultCounts[category], count > 0 {
                            systemRow(JarvisKnowledgeVault.labels[category] ?? category, "\(count)건", scale: scale)
                        }
                    }
                    systemRow("최근 작업 기록", model.activityChecked ? "\(model.recordedActivity.count)건" : "미확인", scale: scale)
                    Rectangle().fill(amber.opacity(0.2)).frame(height: 1)
                    if let vercel = model.vercelSnapshot {
                        if let error = vercel.error {
                            status("Vercel: " + error, scale: scale)
                        }
                        systemRow("Vercel 프로젝트", vercel.error == nil ? "\(vercel.projects.count)개" : "미확인", scale: scale)
                        if vercel.error == nil {
                            let ready = vercel.deployments.filter { $0.state == "READY" }.count
                            let failed = vercel.deployments.filter { $0.state == "ERROR" }.count
                            systemRow("최근 배포", "\(vercel.deployments.count)건 · READY \(ready) / ERROR \(failed)", scale: scale)
                            ForEach(vercel.deployments.prefix(5)) { deployment in
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(deployment.name).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(deployment.state ?? "미확인")
                                        .foregroundStyle(deployment.state == "READY" ? mint : amber)
                                }
                                .font(.system(size: 9 * scale, design: .monospaced))
                                .foregroundStyle(muted)
                            }
                            if vercel.hasMoreDeployments {
                                status("최근 목록 일부만 표시 · 전체 배포 아님", scale: scale)
                            }
                        }
                    } else {
                        status(model.vercelIsLoading ? "Vercel 프로젝트·배포 조회 중…" : "Vercel 조회 준비 중", scale: scale)
                    }
                    systemRow("로컬 갱신 주기", "약 7초", scale: scale)
                    systemRow("GitHub 원격 조회", "10분 / 캐시 재사용", scale: scale)
                    systemRow("Vercel 원격 조회", "15분 / 캐시 재사용", scale: scale)
                    Text("실제 연결 상태 · 외부 API 사용량 미측정")
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.visible)
        }
    }

    private func activityCard(scale: CGFloat) -> some View {
        panel("LIVE CHECKS / 실제 조회 로그", symbol: "terminal", scale: scale) {
            HStack(spacing: 6) {
                Circle().fill(mint).frame(width: 5, height: 5)
                Text("대시보드 표시 중 자동 갱신 · 오류도 기록")
                    .font(.system(size: 9 * scale, design: .monospaced))
                    .foregroundStyle(muted)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.sourceChecks) { check in
                        HStack(alignment: .top, spacing: 6) {
                            Text(check.at.formatted(date: .omitted, time: .standard))
                                .foregroundStyle(muted)
                            Text(check.success ? "OK" : "ERR")
                                .foregroundStyle(check.success ? mint : amber)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.source).foregroundStyle(.white.opacity(0.90))
                                Text(check.detail).foregroundStyle(muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 10 * scale, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.visible)
            .accessibilityIdentifier("jarvis-command-real-checks")
            HStack(spacing: 6) {
                Text(">")
                Text("AWAITING COMMAND")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Int(context.date.timeIntervalSince1970).isMultiple(of: 2) ? "█" : " ")
                }
            }
            .font(.system(size: 10 * scale, design: .monospaced))
            .foregroundStyle(amber)
        }
    }

    private func recordedCard(scale: CGFloat) -> some View {
        panel("RECORDED EVENTS / DECHIVE 기록 원장", symbol: "clock.arrow.circlepath", scale: scale) {
            if model.activityChecked {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.recordedActivity.prefix(10)) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(String(event.createdAt.prefix(16)))
                                    .foregroundStyle(muted)
                                Text(event.category)
                                    .foregroundStyle(mint)
                                Spacer(minLength: 3)
                                Text(event.result)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .font(.system(size: 9 * scale, design: .monospaced))
                        }
                        if model.recordedActivity.isEmpty {
                            status("아직 기록된 작업 이벤트가 없습니다.", scale: scale)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.visible)
            } else {
                status("기록 원장 연결 실패 또는 조회 중", scale: scale)
            }
            Text("표시된 날짜는 실제 기록 시각입니다. 오늘 실행한 작업이라는 뜻이 아닙니다.")
                .font(.system(size: 9 * scale))
                .foregroundStyle(muted)
                .lineLimit(2)
        }
    }

    private func progress(_ completed: Int, total: Int) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.13))
                Capsule().fill(amber)
                    .frame(width: geometry.size.width * CGFloat(completed) / CGFloat(max(1, total)))
            }
        }
        .frame(height: 5)
    }

    private func labelValue(_ name: String, _ value: String, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).foregroundStyle(muted)
                .font(.system(size: 10 * scale))
            Text(value).foregroundStyle(.white)
                .font(.system(size: 15 * scale, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func systemRow(_ name: String, _ value: String, scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(muted)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(.white).lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 11 * scale, design: .monospaced))
    }

    private func status(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 11 * scale))
            .foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
