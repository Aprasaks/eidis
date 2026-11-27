import SwiftUI

/// First native iPhone companion to the current macOS JARVIS.
/// The primary Mac golden core video is real; Mac remote control is not yet paired.
struct JARVISHomeView: View {
    /// 아래 탭 막대에 있는 화면. 나머지는 상단 뒤로가기 버튼을 보여준다.
    static let tabPages: Set<JARVISMobilePage> = [.core, .dashboard, .alarm, .calendar, .memory]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var voice = JARVISVoice()
    @AppStorage(JARVISWakeConfirmation.timestampKey) private var lastWakeConfirmedAt = 0.0
    @StateObject private var alarms = JARVISAlarmStore()
    @StateObject private var calendar: JARVISCalendarStore
    @StateObject private var nearby: JARVISMobileNearbyCalendar

    init() {
        let calendar = JARVISCalendarStore(notifications: .current())
        _calendar = StateObject(wrappedValue: calendar)
        _nearby = StateObject(wrappedValue: JARVISMobileNearbyCalendar(calendar: calendar))
    }
    @State private var selectedPage: JARVISMobilePage = JARVISMobilePage.initialPageForVerification
    @State private var prompt = ""
    @State private var showingVoiceSettings = false
    @State private var proposedEvent: JARVISCalendarDraft?
    @State private var showingCalendarManualEntry = false
    @State private var showingAlarmManualEntry = false
    @FocusState private var inputFocused: Bool

    private var active: Bool {
        scenePhase == .active && !reduceMotion
    }

    var body: some View {
        ZStack {
            JARVISPalette.black.ignoresSafeArea()

            RadialGradient(
                colors: [JARVISPalette.gold.opacity(0.085), .clear],
                center: UnitPoint(x: 0.5, y: 0.43),
                startRadius: 26,
                endRadius: 360
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)
                    .padding(.horizontal, 23)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if selectedPage == .core {
                            coreArea
                            greeting
                            quickCommands
                                .padding(.top, 25)
                        } else if selectedPage == .alarm {
                            JARVISAlarmView(store: alarms)
                        } else if selectedPage == .dashboard {
                            JARVISMobileDashboardView(calendar: calendar, nearby: nearby) { destination in
                                selectedPage = destination
                            }
                        } else {
                            // 아래 탭에 없는 화면(SNS·프로젝트·뉴스 등)은 돌아갈 곳이 안 보였다.
                            // 상단 "‹ 전체 현황" 버튼과 왼쪽 가장자리 밀기로 전체 현황으로 돌아간다.
                            if !Self.tabPages.contains(selectedPage) {
                                Button { selectedPage = .dashboard } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                                        Text("전체 현황").font(.system(size: 15))
                                    }
                                    .foregroundStyle(JARVISPalette.gold)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("전체 현황으로 돌아가기")
                            }
                            JARVISMobileDataPageView(page: selectedPage, calendar: calendar, nearby: nearby)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .id(selectedPage)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    // 왼쪽 가장자리(32pt 이내)에서 오른쪽으로 밀면 뒤로가기 (iOS 기본 동작과 같은 방향).
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard !Self.tabPages.contains(selectedPage), value.startLocation.x < 32,
                                  value.translation.width > 80, abs(value.translation.height) < 70 else { return }
                            selectedPage = .dashboard
                        }
                )

                navigationBar
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .foregroundStyle(JARVISPalette.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingVoiceSettings) {
            JARVISVoiceSettingsView(service: voice.elevenLabs)
        }
        .sheet(item: $proposedEvent) { proposal in
            JARVISCalendarEditor(store: calendar, proposal: proposal, selectedDate: proposal.startAt)
        }
        .sheet(isPresented: $showingCalendarManualEntry) {
            JARVISCalendarEditor(store: calendar)
        }
        .sheet(isPresented: $showingAlarmManualEntry) {
            JARVISAlarmEditor(store: alarms)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                voice.cancel()
                voice.stopSpeaking()
            }
        }
        .onDisappear {
            voice.cancel()
            voice.stopSpeaking()
        }
        .task {
            nearby.setForeground(scenePhase == .active)
            await calendar.rescheduleUpcomingReminders()
            alarms.refresh()
        }
        .onChange(of: calendar.localRevision) { _, _ in
            nearby.sync()
        }
        .onOpenURL { url in
            // 위젯을 누르면 SNS 화면으로 (jarvis://social)
            if url.scheme == "jarvis", url.host == "social" { selectedPage = .social }
        }
        .onChange(of: scenePhase) { _, phase in
            nearby.setForeground(phase == .active)
            // 앱을 열 때마다 SNS 요약을 받아 위젯도 최신으로 맞춘다 (연결된 Mac이 있을 때만).
            if phase == .active { Task { try? await Task.sleep(for: .seconds(2)); nearby.refreshSocial() } }
            if phase == .active {
                nearby.sync()
                alarms.refresh()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("EIDIS")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .tracking(4)
            Spacer()
            Button {
                showingVoiceSettings = true
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(JARVISPalette.gold)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("목소리 설정")
        }
    }

    private var coreArea: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            JARVISPalette.gold.opacity(voice.isListening ? 0.18 : 0.095),
                            JARVISPalette.gold.opacity(0.035),
                            .clear
                        ],
                        center: .center,
                        startRadius: 12,
                        endRadius: 150
                    )
                )
                .frame(width: 330, height: 330)
                .blur(radius: 23)

            // The same ORIGINAL golden Mac overlay animation, cropped only
            // to remove its baked-in caption and fit this iPhone square.
            // No reconstructed SceneKit lookalike.
            if let videoURL = Bundle.main.url(forResource: "DECHIVE_Core_Mobile", withExtension: "mp4") {
                JarvisLoopingCoreMobile(videoURL: videoURL, active: active)
                    .frame(width: 330, height: 330)
                    // The Mac original has a subtle warm-black background.
                    // Feather ONLY the square crop edges to blend naturally
                    // into the phone backdrop without trimming the gold ring.
                    .mask {
                        RadialGradient(stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.78),
                            .init(color: .clear, location: 1)
                        ], center: .center, startRadius: 0, endRadius: 184)
                    }
                    .accessibilityLabel(active
                        ? "맥 이디스 원본 금빛 코어 애니메이션 재생 중"
                        : "맥 이디스 원본 금빛 코어 애니메이션 일시정지")
                    .accessibilityAddTraits(.isImage)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(JARVISPalette.gold)
                    Text("원본 코어 리소스를 찾을 수 없어요")
                        .font(.caption)
                        .foregroundStyle(JARVISPalette.muted)
                }
                .frame(width: 330, height: 330)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 326)
        .padding(.top, 10)
    }

    private var greeting: some View {
        VStack(spacing: 10) {
            Text("안녕하세요 DECHIVE!")
                .font(.system(size: 23, weight: .medium))
                .tracking(-0.7)
                .multilineTextAlignment(.center)
            if lastWakeConfirmedAt > 0,
               Calendar.current.isDateInToday(Date(timeIntervalSince1970: lastWakeConfirmedAt)) {
                Label("기상 확인 완료", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(JARVISPalette.gold)
            }
            if voice.isListening {
                Text("듣고 있어요")
                    .font(.system(size: 12))
                    .foregroundStyle(JARVISPalette.gold)
            }
        }
        .padding(.top, 2)
    }

    private var quickCommands: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                quickAction(.dashboard)
                quickAction(.alarm)
            }
        }
    }

    private func quickAction(_ page: JARVISMobilePage) -> some View {
        Button { selectedPage = page } label: {
            HStack(spacing: 10) {
                Image(systemName: page.icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(JARVISPalette.gold)
                Text(page.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(JARVISPalette.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13)
                .stroke(JARVISPalette.panelEdge, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .accessibilityHint("해당 화면을 엽니다. Mac의 실제 데이터는 연결 전까지 표시하지 않습니다.")
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            ForEach([JARVISMobilePage.core, .dashboard, .alarm, .calendar, .memory]) { page in
                Button {
                    selectedPage = page
                    inputFocused = false
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: page.icon)
                            .font(.system(size: 17, weight: .medium))
                        Text(page.title)
                            .font(.system(size: 10, weight: selectedPage == page ? .semibold : .regular))
                    }
                    .foregroundStyle(selectedPage == page ? JARVISPalette.gold : JARVISPalette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 51)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
        .background(JARVISPalette.black)
        .overlay(alignment: .top) {
            JARVISPalette.panelEdge.frame(height: 0.5)
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("이디스에게 말하기…", text: $prompt)
                .font(.system(size: 14))
                .submitLabel(.send)
                .focused($inputFocused)
                .onSubmit(submitPrompt)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(JARVISPalette.panel, in: Capsule())
                .overlay(Capsule().stroke(JARVISPalette.panelEdge))
                .accessibilityLabel("이디스 텍스트 명령")

            if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: submitPrompt) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 39))
                        .foregroundStyle(JARVISPalette.gold)
                }
                .accessibilityLabel("메시지 전송")
            } else {
                Button {
                    toggleMicrophone()
                } label: {
                    Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(JARVISPalette.black)
                        .frame(width: 48, height: 48)
                        .background(JARVISPalette.gold, in: Circle())
                }
                .disabled(voice.busy)
                .accessibilityLabel(voice.isListening ? "음성 인식 완료" : "음성 인식 시작")
            }
        }
        .padding(.horizontal, 19)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(JARVISPalette.black.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(JARVISPalette.gold.opacity(0.13))
                .frame(height: 0.5)
        }
    }

    private func toggleMicrophone() {
        inputFocused = false
        if voice.isListening {
            Task {
                if let text = await voice.finish() {
                    dispatch(text)
                }
            }
        } else {
            Task { await voice.start() }
        }
    }

    private func submitPrompt() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt = ""
        inputFocused = false
        dispatch(text)
    }

    private func dispatch(_ input: String) {
        let compact = input.lowercased().replacingOccurrences(of: " ", with: "")
        if (["알람", "모닝콜", "깨워"].contains { compact.contains($0) }) &&
           (["맞춰", "설정", "추가", "등록", "깨워"].contains { compact.contains($0) }) {
            selectedPage = .alarm
            showingAlarmManualEntry = true
            voice.speak("DECHIVE, 이디스 알람 작성 화면을 열었어요. 시간을 확인하고 저장을 눌러 주세요.", for: input)
            return
        }
        if let proposal = JARVISCalendarSpeechParser.parse(input) {
            selectedPage = .calendar
            proposedEvent = proposal
            voice.speak("DECHIVE, \(proposal.evidence)으로 이해했어요. 내용을 확인하고 저장을 눌러 주세요.", for: input)
            return
        }
        if JARVISCalendarSpeechParser.requestsCreation(input) {
            selectedPage = .calendar
            showingCalendarManualEntry = true
            voice.speak("DECHIVE, 날짜나 오전·오후가 불분명해요. 일정 확인 화면에서 정확한 시간을 지정해 주세요.", for: input)
            return
        }
        if let page = JARVISMobilePage.requestedPage(for: input) {
            selectedPage = page
            voice.speak(page.spokenStatus, for: input)
        } else {
            let answer = JARVISCommand.response(to: input)
            voice.speak(answer, for: input)
        }
    }
}

#Preview {
    JARVISHomeView()
}
