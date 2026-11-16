import SwiftUI

// EIDIS iPhone 0.3: restrained black interface, not a glass or demo HUD.
// The existing app bundle identifier stays unchanged for in-place updates.

private enum EIDISLook {
    static let black = Color(red: 0.008, green: 0.011, blue: 0.018)
    static let panel = Color(red: 0.058, green: 0.069, blue: 0.088)
    static let panelRaised = Color(red: 0.077, green: 0.091, blue: 0.115)
    static let line = Color.white.opacity(0.115)
    static let accent = Color(red: 0.31, green: 0.82, blue: 0.91)
    static let white = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let muted = Color(red: 0.63, green: 0.67, blue: 0.72)
}

private struct EIDISCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                EIDISLook.panel,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(EIDISLook.line, lineWidth: 0.8)
            }
    }
}

/// A very low-contrast black/navy backdrop. No animated starfield,
/// fake detection labels or rendered camera footage.
private struct EIDISBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                EIDISLook.black
                RadialGradient(
                    colors: [
                        Color(red: 0.043, green: 0.098, blue: 0.14),
                        EIDISLook.black.opacity(0.96),
                        EIDISLook.black
                    ],
                    center: UnitPoint(x: 0.54, y: 0.44),
                    startRadius: 25,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.67
                )
                .opacity(0.48)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

struct JARVISHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = JARVISCamera()
    @StateObject private var voice = JARVISVoice()
    @StateObject private var weather = EIDISWeatherService()
    @StateObject private var personal = EIDISPersonalData()
    @State private var activeService: EIDISService?
    @State private var showComposer = false
    @State private var showFeatures = false
    @State private var showTranscript = false
    @State private var textCommand = ""

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if (5..<12).contains(hour) { return "좋은 아침입니다." }
        if (12..<18).contains(hour) { return "좋은 오후입니다." }
        return "안녕하세요."
    }

    private var voiceStatus: String {
        if voice.isListening { return "음성 인식 중" }
        if voice.busy { return "인식 처리 중" }
        return "로컬 음성 대기"
    }

    var body: some View {
        ZStack {
            if camera.isLive {
                JARVISCameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                EIDISBackdrop()
            }

            if camera.isLive {
                EIDISLook.black.opacity(0.22).ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 11)
                    .padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 17) {
                        greetingPanel
                        servicesRow

                        EIDISCoreView(
                            listening: voice.isListening,
                            cameraLive: camera.isLive,
                            active: scenePhase == .active
                        )
                            .frame(height: 205)
                            .padding(.vertical, 1)

                        connectionNotice
                        conversationCard
                        memoryCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 11)
                    .padding(.bottom, 18)
                }

                dock
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background {
                        LinearGradient(
                            colors: [EIDISLook.black.opacity(0.64), EIDISLook.black],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
            }
        }
        .foregroundStyle(EIDISLook.white)
        .preferredColorScheme(.dark)
        .sheet(item: $activeService) { service in
            EIDISServiceSheet(
                service: service,
                personal: personal,
                weather: weather
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await personal.refreshAuthorized()
        }
        .sheet(isPresented: $showComposer) {
            composerSheet
                .presentationDetents([.height(270)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFeatures) {
            featuresSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTranscript) {
            transcriptSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                camera.stop()
                voice.cancel()
                voice.stopSpeaking()
            } else {
                Task { await personal.refreshAuthorized() }
            }
        }
        .onDisappear {
            camera.stop()
            voice.cancel()
            voice.stopSpeaking()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button { showFeatures = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .light))
                    .frame(width: 43, height: 43)
                    .foregroundStyle(EIDISLook.white)
            }
            .accessibilityLabel("기능 연결 상태 보기")

            Spacer()
            VStack(spacing: 3) {
                Text("EIDIS")
                    .font(.system(size: 25, weight: .light, design: .rounded))
                    .tracking(5.5)
                    .foregroundStyle(EIDISLook.white)
                Text("PERSONAL AI ASSISTANT")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(EIDISLook.muted)
            }
            Spacer()

            Button { showFeatures = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 43, height: 43)
                    .foregroundStyle(EIDISLook.white)
            }
            .accessibilityLabel("EIDIS 시스템 상태")
        }
        .frame(maxWidth: .infinity)
    }

    private var greetingPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(greeting)
                .font(.system(size: 29, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(EIDISLook.white)
            Text("마이크를 누르고 “애기야”라고 말해 보세요.")
                .font(.system(size: 14))
                .foregroundStyle(EIDISLook.muted)
            HStack(spacing: 8) {
                Circle()
                    .fill(voice.isListening ? Color.green : EIDISLook.accent)
                    .frame(width: 6, height: 6)
                Text(voiceStatus)
                Text("·")
                Text("AI 연결 전")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(EIDISLook.muted)
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var servicesRow: some View {
        HStack(spacing: 10) {
            Button { activeService = .weather } label: {
                serviceCard(icon: "cloud", title: "현재 날씨", value: weather.displayValue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("실제 날씨 연결 및 상세 보기")
            Button { activeService = .calendar } label: {
                serviceCard(icon: "calendar", title: "다음 일정", value: personal.calendarStatus)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("iPhone 캘린더 연결 및 일정 보기")
        }
    }

    private func serviceCard(icon: String, title: String, value: String) -> some View {
        EIDISCard {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(EIDISLook.accent)
                    .frame(width: 23)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(EIDISLook.muted)
                    Text(value)
                        .font(.system(size: 15, weight: .semibold))
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionNotice: some View {
        HStack(spacing: 9) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 15))
                .foregroundStyle(EIDISLook.accent)
            Text(camera.isLive ? "CAMERA LIVE" : "CAMERA OFF")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.5)
            Spacer(minLength: 0)
            Text("물체 분석 연결 전")
                .font(.system(size: 10))
                .foregroundStyle(EIDISLook.muted)
        }
        .padding(.horizontal, 5)
    }

    private var conversationCard: some View {
        Button { showTranscript = true } label: {
            EIDISCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text("EIDIS")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(EIDISLook.accent)
                        Spacer()
                        Text("LOCAL")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(EIDISLook.muted)
                    }
                    Text(voice.reply)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(EIDISLook.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !voice.transcript.isEmpty {
                        Text("인식: \(voice.transcript)")
                            .font(.system(size: 11))
                            .foregroundStyle(EIDISLook.muted)
                            .lineLimit(1)
                    }
                    HStack {
                        Text(voice.status)
                            .font(.system(size: 10))
                            .foregroundStyle(EIDISLook.muted)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                            .foregroundStyle(EIDISLook.muted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("인식된 문장과 EIDIS 응답 전체 보기")
    }

    private var memoryCard: some View {
        Button { activeService = .reminders } label: {
            EIDISCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.square")
                            .foregroundStyle(EIDISLook.accent)
                        Text("오늘의 작업 · 미리 알림")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(personal.remindersStatus)
                            .font(.system(size: 11))
                            .foregroundStyle(EIDISLook.muted)
                            .lineLimit(1)
                    }
                    if personal.remindersConnected, let next = personal.tasks.first {
                        Text(next.title)
                            .font(.system(size: 12))
                            .foregroundStyle(EIDISLook.muted)
                            .lineLimit(1)
                    } else {
                        Text("iPhone 미리 알림을 연결하세요. Mac 프로젝트 작업과는 별개입니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(EIDISLook.muted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("iPhone 미리 알림 연결 및 작업 보기")
    }

    private var dock: some View {
        VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 15) {
                dockButton(
                    icon: "keyboard", title: "텍스트",
                    accessibility: "텍스트 입력"
                ) { showComposer = true }

                Spacer(minLength: 0)

                Button {
                    if voice.isListening {
                        Task {
                            if let command = await voice.finish() {
                                await handleCommand(command)
                            }
                        }
                    } else {
                        Task { await voice.start() }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(EIDISLook.panelRaised)
                            .frame(width: 78, height: 78)
                        Circle()
                            .strokeBorder(EIDISLook.accent.opacity(
                                voice.isListening ? 0.95 : 0.75), lineWidth: 1.6)
                            .frame(width: 78, height: 78)
                        Image(systemName: voice.isListening ? "stop.fill" : "mic")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(EIDISLook.white)
                    }
                    .frame(width: 83, height: 83)
                }
                .buttonStyle(.plain)
                .disabled(voice.busy)
                .accessibilityLabel(voice.isListening ? "음성 녹음 완료" : "음성 시작")

                Spacer(minLength: 0)

                dockButton(
                    icon: camera.isLive ? "video.slash" : "camera",
                    title: camera.isLive ? "끄기" : "카메라",
                    accessibility: camera.isLive ? "카메라 끄기" : "카메라"
                ) {
                    if camera.isLive {
                        camera.stop()
                    } else {
                        Task { await camera.start() }
                    }
                }
            }
            .frame(height: 86)

            HStack(spacing: 9) {
                if voice.isListening || voice.busy {
                    Button("취소") { voice.cancel() }
                        .font(.system(size: 11))
                        .foregroundStyle(EIDISLook.accent)
                }
                Text(voice.isListening ? "듣고 있습니다 · 다시 눌러 완료" :
                     voice.busy ? "인식 확정 중" : "눌러서 말하기")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EIDISLook.muted)
            }
        }
    }

    private func dockButton(
        icon: String, title: String,
        accessibility: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(EIDISLook.white)
            .frame(width: 69, height: 69)
            .background(
                EIDISLook.panel,
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 19)
                    .strokeBorder(EIDISLook.line, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private var composerSheet: some View {
        NavigationStack {
            ZStack {
                EIDISLook.black.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 15) {
                    Text("EIDIS에게 질문")
                        .font(.system(size: 19, weight: .semibold))
                    TextField("예: 애기야, 날씨 알려줘", text: $textCommand)
                        .submitLabel(.send)
                        .padding(13)
                        .background(
                            EIDISLook.panel,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .onSubmit { sendTyped() }
                    Button("전달") { sendTyped() }
                        .buttonStyle(.borderedProminent)
                        .tint(EIDISLook.accent)
                        .disabled(textCommand.trimmingCharacters(
                            in: .whitespacesAndNewlines).isEmpty)
                    Text("AI 서버 연결 전 · 지금은 기기 내 기본 응답만 제공됩니다.")
                        .font(.caption2)
                        .foregroundStyle(EIDISLook.muted)
                }
                .padding(22)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { showComposer = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var featuresSheet: some View {
        NavigationStack {
            ZStack {
                EIDISLook.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("EIDIS 0.4 · 연결 현황")
                            .font(.title3.weight(.semibold))
                        feature("camera", "후면 카메라", "사용자가 켰을 때 실시간 영상")
                        feature("waveform", "한국어 음성", "기기 내 인식 및 음성 출력")
                        feature("brain", "개인 AI", "연결 전")
                        feature("cloud", "현재 날씨", weather.displayValue)
                        feature("calendar", "캘린더", personal.calendarStatus)
                        feature("checkmark.square", "미리 알림", personal.remindersStatus)
                        feature("map", "길 안내", "연결 전")
                        feature("eye", "카메라 사물 분석", "연결 전")
                        feature("desktopcomputer", "Mac 프로젝트 기억", "연결 전")
                        Text("이 화면은 검증되지 않은 분석 결과를 표시하지 않습니다.")
                            .font(.caption)
                            .foregroundStyle(EIDISLook.muted)
                    }
                    .padding(22)
                }
            }
            .navigationTitle("시스템 상태")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { showFeatures = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        EIDISCard {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(EIDISLook.accent)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(EIDISLook.muted)
                }
            }
        }
    }

    private var transcriptSheet: some View {
        NavigationStack {
            ZStack {
                EIDISLook.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("인식된 문장")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EIDISLook.accent)
                        Text(voice.transcript.isEmpty
                             ? "아직 인식된 문장이 없습니다." : voice.transcript)
                            .textSelection(.enabled)
                        Divider()
                        Text("EIDIS 응답")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EIDISLook.accent)
                        Text(voice.reply)
                            .textSelection(.enabled)
                        Text(voice.status)
                            .font(.caption)
                            .foregroundStyle(EIDISLook.muted)
                        Button("음성 출력 중지") { voice.stopSpeaking() }
                            .foregroundStyle(EIDISLook.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(23)
                }
            }
            .navigationTitle("대화")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { showTranscript = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func handleCommand(_ command: String) async {
        let answer: String
        switch EIDISCommand.intent(for: command) {
        case .weather:
            answer = weather.readout()
        case .calendar:
            if personal.calendarConnected { await personal.reloadEvents() }
            answer = personal.calendarReadout()
        case .reminders:
            if personal.remindersConnected { await personal.reloadReminders() }
            answer = personal.remindersReadout()
        case .greeting, .help, .unsupported, .unknown:
            answer = JARVISResponse.answer(to: command)
        }
        voice.speak(answer, for: command)
    }

    private func sendTyped() {
        let command = textCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        textCommand = ""
        showComposer = false
        Task { await handleCommand(command) }
    }
}

#Preview {
    JARVISHomeView()
}
