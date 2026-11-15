import SwiftUI

// JARVIS iPhone 0.2 — cinematic, camera-first interface.
// All data cards are truthful: no weather, calendar, navigation, live vision AI,
// or Mac-memory sync is claimed unless a provider is actually connected.

private enum HUDStyle {
    static let ink = Color(red: 0.018, green: 0.039, blue: 0.082)
    static let navy = Color(red: 0.036, green: 0.105, blue: 0.161)
    static let cyan = Color(red: 0.32, green: 0.94, blue: 0.99)
    static let electric = Color(red: 0.13, green: 0.57, blue: 0.99)
    static let mist = Color(red: 0.82, green: 0.95, blue: 1)
    static let secondary = Color(red: 0.70, green: 0.83, blue: 0.91)

    static let accent = LinearGradient(
        colors: [cyan, electric], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let glassFill = LinearGradient(
        colors: [
            Color(red: 0.13, green: 0.25, blue: 0.34).opacity(0.83),
            Color(red: 0.035, green: 0.085, blue: 0.145).opacity(0.85)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let glassStroke = LinearGradient(
        colors: [
            cyan.opacity(0.63),
            .white.opacity(0.13),
            electric.opacity(0.33),
            cyan.opacity(0.22)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

private struct HUDGlass<Content: View>: View {
    let radius: CGFloat
    @ViewBuilder let content: Content

    init(radius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(HUDStyle.glassFill)
                    .background(
                        .ultraThinMaterial.opacity(0.22),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(HUDStyle.glassStroke, lineWidth: 0.85)
            }
            .shadow(color: .black.opacity(0.32), radius: 15, y: 7)
    }
}

private struct HUDReticle: View {
    let cameraLive: Bool
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let corner: CGFloat = min(31, height * 0.15)
            let margin: CGFloat = 11
            ZStack {
                Path { path in
                    func cornerPath(_ x: CGFloat, _ y: CGFloat,
                                    _ dx: CGFloat, _ dy: CGFloat) {
                        path.move(to: CGPoint(x: x, y: y + dy * corner))
                        path.addLine(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x + dx * corner, y: y))
                    }
                    cornerPath(margin, margin, 1, 1)
                    cornerPath(width - margin, margin, -1, 1)
                    cornerPath(margin, height - margin, 1, -1)
                    cornerPath(width - margin, height - margin, -1, -1)
                }
                .stroke(HUDStyle.cyan.opacity(0.95),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .shadow(color: HUDStyle.cyan.opacity(0.75), radius: 7)

                Circle()
                    .stroke(HUDStyle.cyan.opacity(0.35), lineWidth: 0.75)
                    .frame(width: 75, height: 75)
                Circle()
                    .trim(from: 0.02, to: 0.18)
                    .stroke(HUDStyle.cyan.opacity(0.77),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0.52, to: 0.68)
                    .stroke(HUDStyle.cyan.opacity(0.77),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .ultraLight))
                    .foregroundStyle(HUDStyle.mist)

                VStack(spacing: 0) {
                    HStack {
                        Text("OPTICAL INTERFACE")
                        Spacer()
                        Text(cameraLive ? "LIVE VIEW" : "STANDBY")
                    }
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(HUDStyle.cyan.opacity(0.86))
                    .padding(.horizontal, 23)
                    .padding(.top, 23)

                    Spacer(minLength: 0)

                    if !cameraLive {
                        VStack(spacing: 5) {
                            Text("HUD PREVIEW")
                                .font(.system(size: 10, weight: .semibold,
                                              design: .monospaced))
                                .tracking(2)
                                .foregroundStyle(HUDStyle.cyan)
                            Text("카메라 버튼을 눌러 실시간 화면을 시작하세요")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.77))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(HUDStyle.ink.opacity(0.65), in: Capsule())
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 7) {
                        Image(systemName: "viewfinder")
                        Text("물체 분석 연결 전")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HUDStyle.mist.opacity(0.90))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.52), in: Capsule())
                    .overlay(Capsule().stroke(HUDStyle.cyan.opacity(0.26)))
                    .padding(.bottom, 19)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(cameraLive
            ? "후면 카메라 실시간 미리보기, AI 분석은 연결 전"
            : "카메라가 꺼진 HUD 미리보기")
    }
}

private struct HUDBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                LinearGradient(
                    colors: [
                        HUDStyle.ink, Color(red: 0.046, green: 0.15, blue: 0.23),
                        Color(red: 0.10, green: 0.22, blue: 0.30),
                        HUDStyle.ink
                    ], startPoint: .top, endPoint: .bottom
                )
                Ellipse()
                    .fill(HUDStyle.electric.opacity(0.32))
                    .frame(width: w * 0.95, height: h * 0.32)
                    .blur(radius: 77)
                    .offset(x: w * 0.2, y: -h * 0.08)
                Circle()
                    .fill(Color(red: 0.98, green: 0.66, blue: 0.36).opacity(0.16))
                    .frame(width: w * 0.4)
                    .blur(radius: 65)
                    .offset(x: -w * 0.23, y: h * 0.22)

                Canvas { context, size in
                    let horizon = size.height * 0.58
                    for index in 0..<15 {
                        let step = size.width / 15
                        let x = CGFloat(index) * step
                        let variance = CGFloat((index * 29 + 13) % 105)
                        let top = horizon - 75 - variance
                        let building = CGRect(
                            x: x - 1, y: top,
                            width: step + 1, height: size.height - top)
                        context.fill(Path(building), with: .color(
                            Color(red: 0.015, green: 0.063, blue: 0.10)
                                .opacity(index.isMultiple(of: 3) ? 0.83 : 0.64)))
                        for floor in 0..<7 {
                            let window = CGRect(
                                x: x + 6, y: top + 12 + CGFloat(floor) * 17,
                                width: 2.4, height: 5)
                            context.fill(Path(window), with: .color(
                                HUDStyle.cyan.opacity(floor.isMultiple(of: 2) ? 0.22 : 0.09)))
                        }
                    }

                    let vanishing = CGPoint(x: size.width * 0.52, y: horizon)
                    for index in 0...10 {
                        let x = CGFloat(index) * size.width / 10
                        var path = Path()
                        path.move(to: vanishing)
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path,
                                       with: .color(HUDStyle.cyan.opacity(0.15)),
                                       lineWidth: 0.6)
                    }
                    for index in 1...10 {
                        let fraction = CGFloat(index) / 10
                        let y = horizon + (size.height - horizon) * fraction * fraction
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path,
                                       with: .color(HUDStyle.cyan.opacity(0.11)),
                                       lineWidth: 0.65)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HUDService: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HUDGlass(radius: 17) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .ultraLight))
                    .foregroundStyle(HUDStyle.cyan)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HUDStyle.secondary)
                    Text(value)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct JARVISHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = JARVISCamera()
    @StateObject private var voice = JARVISVoice()
    @State private var showComposer = false
    @State private var showFeatures = false
    @State private var showTranscript = false
    @State private var textCommand = ""

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if (5..<12).contains(hour) { return "좋은 아침이에요." }
        if (12..<18).contains(hour) { return "좋은 오후예요." }
        return "안녕하세요."
    }

    private var cameraLabel: String {
        switch camera.state {
        case .idle: return "카메라 대기"
        case .requesting: return "카메라 권한 확인"
        case .live: return "CAMERA LIVE"
        case .unavailable: return "카메라 사용 불가"
        }
    }

    private var voiceLabel: String {
        if voice.isListening { return "듣고 있어요" }
        if voice.busy { return "음성 처리 중" }
        return "눌러서 말하기"
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if camera.isLive {
                    JARVISCameraPreview(session: camera.session)
                        .ignoresSafeArea()
                } else {
                    HUDBackdrop()
                        .ignoresSafeArea()
                }

                LinearGradient(
                    stops: [
                        .init(color: HUDStyle.ink.opacity(0.90), location: 0),
                        .init(color: HUDStyle.ink.opacity(0.41), location: 0.20),
                        .init(color: .clear, location: 0.44),
                        .init(color: HUDStyle.ink.opacity(0.20), location: 0.60),
                        .init(color: HUDStyle.ink.opacity(0.90), location: 1.0)
                    ], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    header
                    greetingPanel
                        .padding(.top, 12)
                    serviceRow
                        .padding(.top, 12)

                    HUDReticle(cameraLive: camera.isLive)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 140)
                        .padding(.vertical, 10)

                    conversationCard
                        .padding(.bottom, 13)
                    commandDock
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, max(4, geometry.safeAreaInsets.bottom == 0 ? 12 : 2))
            }
        }
        .sheet(isPresented: $showComposer) {
            composerSheet
                .presentationDetents([.height(250)])
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
            }
        }
        .onDisappear {
            camera.stop()
            voice.cancel()
            voice.stopSpeaking()
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .stroke(HUDStyle.cyan.opacity(0.62), lineWidth: 1)
                    .frame(width: 39, height: 39)
                Circle()
                    .trim(from: 0.08, to: 0.35)
                    .stroke(HUDStyle.cyan, lineWidth: 2)
                    .frame(width: 33, height: 33)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "cpu")
                    .font(.system(size: 17, weight: .ultraLight))
                    .foregroundStyle(HUDStyle.mist)
            }
            .shadow(color: HUDStyle.cyan.opacity(0.27), radius: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text("JARVIS")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(.white)
                Text("PERSONAL ASSISTANT")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(HUDStyle.cyan)
            }
            Spacer(minLength: 0)
            Button { showFeatures = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(HUDStyle.mist)
                    .frame(width: 42, height: 42)
                    .background(HUDStyle.navy.opacity(0.78), in: Circle())
                    .overlay(Circle().stroke(HUDStyle.cyan.opacity(0.28)))
            }
            .accessibilityLabel("기능 연결 상태 보기")
        }
    }

    private var greetingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(voice.isListening ? Color.green : HUDStyle.cyan)
                    .frame(width: 6, height: 6)
                    .shadow(color: HUDStyle.cyan, radius: 5)
                Text(cameraLabel)
                Text("·")
                Text(voice.isListening ? "MIC ON" : "LOCAL VOICE")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(HUDStyle.mist.opacity(0.91))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.black.opacity(0.44), in: Capsule())
            .overlay(Capsule().stroke(HUDStyle.cyan.opacity(0.18)))

            HStack(alignment: .center, spacing: 11) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(HUDStyle.accent)
                    .frame(width: 3, height: 49)
                    .shadow(color: HUDStyle.cyan.opacity(0.68), radius: 6)
                VStack(alignment: .leading, spacing: 5) {
                    Text(greeting)
                        .font(.system(size: 27, weight: .semibold))
                        .tracking(-0.55)
                        .foregroundStyle(.white)
                    Text("무엇을 도와드릴까요?")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(HUDStyle.mist.opacity(0.86))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var serviceRow: some View {
        HStack(spacing: 10) {
            HUDService(icon: "cloud.sun", title: "현재 날씨", value: "연결 전")
            HUDService(icon: "calendar", title: "다음 일정", value: "연결 전")
        }
    }

    private var conversationCard: some View {
        Button { showTranscript = true } label: {
            HUDGlass(radius: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("JARVIS · VOICE", systemImage: "waveform")
                            .font(.system(size: 10, weight: .semibold,
                                          design: .monospaced))
                            .tracking(0.9)
                            .foregroundStyle(HUDStyle.cyan)
                        Spacer()
                        if voice.isListening || voice.busy {
                            Circle().fill(HUDStyle.cyan)
                                .frame(width: 6, height: 6)
                        }
                        Text(voice.isListening ? "LISTENING" :
                             voice.busy ? "PROCESSING" : "LOCAL")
                            .font(.system(size: 9, weight: .medium,
                                          design: .monospaced))
                            .foregroundStyle(HUDStyle.secondary)
                    }

                    HStack(spacing: 9) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(HUDStyle.secondary)
                        Text(voice.transcript.isEmpty
                             ? "인식된 음성은 여기에 표시됩니다."
                             : voice.transcript)
                            .font(.system(size: 11))
                            .foregroundStyle(HUDStyle.mist.opacity(
                                voice.transcript.isEmpty ? 0.63 : 0.95))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 15))
                            .foregroundStyle(HUDStyle.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(voice.reply)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            Text(voice.status)
                                .font(.system(size: 10))
                                .foregroundStyle(HUDStyle.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                            .foregroundStyle(HUDStyle.cyan.opacity(0.75))
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("인식된 문장과 자비스 응답 전체 보기")
    }

    private var commandDock: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 5) {
                dockSideButton(icon: "keyboard", label: "텍스트") {
                    showComposer = true
                }
                Spacer(minLength: 0)

                HUDWaveform(isActive: voice.isListening)
                    .frame(width: 43, height: 35)

                Button {
                    if voice.isListening {
                        Task { await voice.finish() }
                    } else {
                        Task { await voice.start() }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(HUDStyle.cyan.opacity(0.10))
                            .frame(width: 94, height: 94)
                        Circle()
                            .stroke(HUDStyle.cyan.opacity(0.83), lineWidth: 1.3)
                            .frame(width: 83, height: 83)
                        Circle()
                            .fill(RadialGradient(
                                colors: [
                                    HUDStyle.electric.opacity(0.91),
                                    HUDStyle.navy,
                                    HUDStyle.ink
                                ], center: .topLeading, startRadius: 0, endRadius: 70))
                            .frame(width: 75, height: 75)
                        Image(systemName: voice.isListening ? "stop.fill" : "mic")
                            .font(.system(size: 29, weight: .light))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: HUDStyle.cyan.opacity(
                        voice.isListening ? 0.81 : 0.36), radius: voice.isListening ? 21 : 12)
                }
                .buttonStyle(.plain)
                .disabled(voice.busy)
                .accessibilityLabel(voice.isListening ? "음성 녹음 완료" : "음성 시작")

                HUDWaveform(isActive: voice.isListening)
                    .frame(width: 43, height: 35)

                Spacer(minLength: 0)
                dockSideButton(
                    icon: camera.isLive ? "video.slash" : "camera.viewfinder",
                    label: camera.isLive ? "카메라 끄기" : "카메라"
                ) {
                    if camera.isLive {
                        camera.stop()
                    } else {
                        Task { await camera.start() }
                    }
                }
            }
            .frame(height: 97)

            HStack(spacing: 11) {
                if voice.isListening || voice.busy {
                    Button("취소") { voice.cancel() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HUDStyle.cyan)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(HUDStyle.navy, in: Capsule())
                }
                Text(voiceLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HUDStyle.mist)
                if voice.isListening {
                    Circle().fill(Color.green)
                        .frame(width: 5, height: 5)
                }
            }
            Text("ON-DEVICE VOICE  ·  AI 연결 전")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(HUDStyle.secondary.opacity(0.78))
        }
        .padding(.bottom, 4)
    }

    private func dockSideButton(
        icon: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .ultraLight))
                    .frame(height: 24)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(HUDStyle.mist)
            .frame(width: 67, height: 68)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(HUDStyle.glassFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(HUDStyle.cyan.opacity(0.44), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var composerSheet: some View {
        NavigationStack {
            ZStack {
                HUDStyle.ink.ignoresSafeArea()
                VStack(spacing: 17) {
                    Text("JARVIS에게 직접 입력")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    TextField("예: 자비스, 안녕", text: $textCommand)
                        .submitLabel(.send)
                        .padding(13)
                        .foregroundStyle(.white)
                        .background(HUDStyle.navy, in: RoundedRectangle(cornerRadius: 13))
                        .onSubmit { sendTyped() }
                    Button("명령 전달") { sendTyped() }
                        .buttonStyle(.borderedProminent)
                        .tint(HUDStyle.electric)
                        .disabled(textCommand.trimmingCharacters(
                            in: .whitespacesAndNewlines).isEmpty)
                    Text("현재는 기기 내 기본 응답만 가능하며 외부 AI로 전송하지 않습니다.")
                        .font(.caption2)
                        .foregroundStyle(HUDStyle.secondary)
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
                HUDStyle.ink.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("JARVIS 0.2 · 연결 현황")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        featureRow("camera.viewfinder", "후면 카메라", "사용자 요청 시 실시간 미리보기")
                        featureRow("waveform", "한국어 음성", "기기 내 인식 및 음성 출력")
                        featureRow("brain", "개인 AI 두뇌", "연결 전")
                        featureRow("cloud.sun", "날씨·일정", "연결 전")
                        featureRow("map", "길 안내", "연결 전")
                        featureRow("eye", "카메라 사물 분석", "연결 전")
                        featureRow("desktopcomputer", "Mac JARVIS 기억", "연결 전")
                        Text("화면의 HUD는 카메라 안내 표시입니다. 물체나 장소를 실제로 인식하지 않습니다.")
                            .font(.caption)
                            .foregroundStyle(HUDStyle.secondary)
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

    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HUDGlass(radius: 14) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundStyle(HUDStyle.cyan)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(detail).font(.caption)
                        .foregroundStyle(HUDStyle.secondary)
                }
                Spacer()
            }
            .padding(13)
        }
    }

    private var transcriptSheet: some View {
        NavigationStack {
            ZStack {
                HUDStyle.ink.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("인식된 문장")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HUDStyle.cyan)
                        Text(voice.transcript.isEmpty
                            ? "아직 인식된 문장이 없습니다." : voice.transcript)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                        Divider().overlay(HUDStyle.cyan.opacity(0.2))
                        Text("JARVIS 응답")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HUDStyle.cyan)
                        Text(voice.reply)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                        Text(voice.status)
                            .font(.caption)
                            .foregroundStyle(HUDStyle.secondary)
                        Button("음성 재생 중지") { voice.stopSpeaking() }
                            .foregroundStyle(HUDStyle.cyan)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(23)
                }
            }
            .navigationTitle("대화 내용")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { showTranscript = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sendTyped() {
        let command = textCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        voice.respond(to: command)
        textCommand = ""
        showComposer = false
    }
}

private struct HUDWaveform: View {
    let isActive: Bool
    private let heights: [CGFloat] = [5, 9, 14, 24, 12, 31, 18, 11, 23, 8, 5]

    var body: some View {
        HStack(alignment: .center, spacing: 1.6) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(HUDStyle.cyan.opacity(isActive ? 0.95 : 0.52))
                    .frame(width: 2, height: heights[index])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview {
    JARVISHomeView()
}
