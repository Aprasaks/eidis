import SwiftUI

private struct GlassHUD<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(JARVISPalette.glass.opacity(0.76))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 19))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 19)
                    .stroke(JARVISPalette.cyan.opacity(0.23), lineWidth: 0.8)
            }
    }
}

private struct JARVISScanFrame: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            Path { path in
                let corner: CGFloat = 25
                let inset: CGFloat = 8
                path.move(to: CGPoint(x: inset, y: corner + inset))
                path.addLine(to: CGPoint(x: inset, y: inset))
                path.addLine(to: CGPoint(x: corner + inset, y: inset))
                path.move(to: CGPoint(x: w - corner - inset, y: inset))
                path.addLine(to: CGPoint(x: w - inset, y: inset))
                path.addLine(to: CGPoint(x: w - inset, y: corner + inset))
                path.move(to: CGPoint(x: inset, y: h - corner - inset))
                path.addLine(to: CGPoint(x: inset, y: h - inset))
                path.addLine(to: CGPoint(x: corner + inset, y: h - inset))
                path.move(to: CGPoint(x: w - corner - inset, y: h - inset))
                path.addLine(to: CGPoint(x: w - inset, y: h - inset))
                path.addLine(to: CGPoint(x: w - inset, y: h - corner - inset))
            }
            .stroke(JARVISPalette.cyan, style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
            .shadow(color: JARVISPalette.cyan.opacity(0.75), radius: 9)
            Circle()
                .stroke(JARVISPalette.cyan.opacity(0.38), lineWidth: 0.9)
                .frame(width: 46, height: 46)
                .position(x: w / 2, y: h / 2)
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(JARVISPalette.cyan)
                .position(x: w / 2, y: h / 2)
        }
        .accessibilityLabel("카메라 화면 중앙 안내 표시")
    }
}

/// An explicitly identified simulator illustration, never fake live camera footage.
private struct CameraOfflineScene: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.025, green: 0.080, blue: 0.145),
                        Color(red: 0.052, green: 0.16, blue: 0.23),
                        JARVISPalette.night
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                Canvas { context, size in
                    let skyline = size.height * 0.48
                    // Abstract simulated city silhouette. Not object detection.
                    for index in 0..<12 {
                        let step = size.width / 12
                        let x = CGFloat(index) * step
                        let top = skyline - CGFloat((index * 37 + 29) % 105)
                        let rect = CGRect(x: x, y: top, width: step - 2,
                                          height: size.height - top)
                        context.fill(Path(rect), with: .color(
                            Color(red: 0.055, green: 0.105, blue: 0.15)
                                .opacity(index.isMultiple(of: 3) ? 0.88 : 0.64)))
                        for row in 0..<4 {
                            let y = top + 15 + CGFloat(row) * 20
                            let window = CGRect(x: x + 7, y: y, width: 3, height: 6)
                            context.fill(Path(window), with: .color(
                                JARVISPalette.cyan.opacity(0.14)))
                        }
                    }
                    let horizon = CGPoint(x: size.width * 0.52, y: skyline)
                    for i in 0...8 {
                        let x = CGFloat(i) * size.width / 8
                        var path = Path()
                        path.move(to: horizon)
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(JARVISPalette.cyan.opacity(0.15)),
                                       lineWidth: 0.9)
                    }
                    for i in 1...8 {
                        let progress = pow(Double(i) / 8.0, 1.8)
                        let y = skyline + (size.height - skyline) * CGFloat(progress)
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(JARVISPalette.cyan.opacity(0.13)),
                                       lineWidth: 0.7)
                    }
                }
                .allowsHitTesting(false)
                Circle()
                    .fill(JARVISPalette.blue.opacity(0.16))
                    .frame(width: w * 0.85)
                    .blur(radius: 85)
                    .offset(x: w * 0.25, y: -h * 0.19)
            }
        }
    }
}

struct JARVISHomeView: View {
    @StateObject private var camera = JARVISCamera()
    @StateObject private var voice = JARVISVoice()
    @State private var textCommand = ""
    @State private var showKeyboard = false

    private var cameraLabel: String {
        switch camera.state {
        case .idle: return "카메라 대기"
        case .requesting: return "권한 확인 중"
        case .live: return "CAMERA LIVE"
        case .unavailable: return "카메라 사용 불가"
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if (5..<12).contains(hour) { return "좋은 아침" }
        if (12..<18).contains(hour) { return "좋은 오후" }
        return "안녕하세요"
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if camera.isLive {
                    JARVISCameraPreview(session: camera.session)
                        .ignoresSafeArea()
                } else {
                    CameraOfflineScene()
                        .ignoresSafeArea()
                }

                LinearGradient(
                    colors: [
                        JARVISPalette.night.opacity(0.85),
                        .clear, .clear,
                        JARVISPalette.night.opacity(0.92)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topBar
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            introduction
                            scanner
                                .frame(height: max(135, min(205, geometry.size.height * 0.245)))
                                .padding(.horizontal, 26)
                            HStack(spacing: 10) {
                                statusTile(
                                    symbol: "cloud.sun",
                                    heading: "날씨",
                                    detail: "연결 전"
                                )
                                statusTile(
                                    symbol: "calendar",
                                    heading: "일정",
                                    detail: "연결 전"
                                )
                            }
                            .padding(.horizontal, 1)
                            voicePanel
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 26)
                        .padding(.bottom, 22)
                    }
                }
            }
        }
        .onDisappear {
            camera.stop()
            voice.cancel()
            voice.stopSpeaking()
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("J A R V I S")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    Circle()
                        .fill(camera.isLive ? Color.green : JARVISPalette.cyan)
                        .frame(width: 5, height: 5)
                    Text(cameraLabel.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(JARVISPalette.cyan.opacity(0.9))
                }
            }
            Spacer()
            Button {
                if camera.isLive {
                    camera.stop()
                } else {
                    Task { await camera.start() }
                }
            } label: {
                Image(systemName: camera.isLive ? "video.slash" : "camera.viewfinder")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 46, height: 46)
                    .foregroundStyle(JARVISPalette.cyan)
                    .background(.black.opacity(0.30), in: Circle())
                    .overlay(Circle().stroke(JARVISPalette.cyan.opacity(0.35)))
            }
            .accessibilityLabel(camera.isLive ? "카메라 끄기" : "카메라 시작")
        }
        .padding(.horizontal, 23)
        .padding(.top, 13)
        .padding(.bottom, 13)
        .background(.black.opacity(0.22))
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(greeting)
                .font(.system(size: 35, weight: .semibold))
                .tracking(-1)
            Text("당신의 눈과 귀가 되는 Mac 자비스와 연결될 개인 AI 인터페이스")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.76))
            Text("PRIVATE · ON DEVICE FIRST")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.9)
                .foregroundStyle(JARVISPalette.cyan)
                .padding(.top, 5)
        }
        .shadow(color: .black.opacity(0.5), radius: 8)
    }

    private var scanner: some View {
        ZStack {
            JARVISScanFrame()
            VStack(spacing: 8) {
                Image(systemName: camera.isLive ? "viewfinder" : "eye")
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(JARVISPalette.cyan.opacity(0.95))
                Text(camera.isLive ? "실시간 카메라" : "HUD PREVIEW")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(JARVISPalette.cyan.opacity(0.9))
                if !camera.isLive {
                    Text("우측 상단에서 카메라를 시작하세요")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.top, 74)
        }
    }

    private func statusTile(symbol: String, heading: String, detail: String) -> some View {
        GlassHUD {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(JARVISPalette.cyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text(heading)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.73))
                    Text(detail)
                        .font(.system(size: 15, weight: .semibold))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var voicePanel: some View {
        GlassHUD {
            VStack(spacing: 13) {
                HStack {
                    Label("JARVIS ASSISTANT", systemImage: "waveform.path")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(JARVISPalette.cyan)
                    Spacer()
                    Text(voice.isListening ? "LISTENING" :
                         voice.busy ? "PROCESSING" : "READY")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(voice.isListening ? .green : .white.opacity(0.62))
                }

                HStack(alignment: .center, spacing: 13) {
                    Button {
                        if voice.isListening {
                            Task { await voice.finish() }
                        } else {
                            Task { await voice.start() }
                        }
                    } label: {
                        Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 27, weight: .light))
                            .foregroundStyle(.white)
                            .frame(width: 73, height: 73)
                            .background {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [JARVISPalette.cyan, JARVISPalette.blue.opacity(0.55),
                                                     JARVISPalette.night],
                                            center: .topLeading,
                                            startRadius: 1,
                                            endRadius: 77)
                                    )
                            }
                            .overlay(Circle().stroke(JARVISPalette.cyan, lineWidth: 1.5))
                            .shadow(color: JARVISPalette.cyan.opacity(voice.isListening ? 0.80 : 0.34),
                                    radius: voice.isListening ? 22 : 13)
                    }
                    .buttonStyle(.plain)
                    .disabled(voice.busy)
                    .accessibilityLabel(voice.isListening ? "음성 녹음 완료" : "음성 시작")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(voice.isListening ? "듣고 있습니다" :
                             voice.busy ? "인식 확정 중" : "자비스에게 말하기")
                            .font(.system(size: 18, weight: .medium))
                        Text(voice.status)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.73))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if voice.isListening || voice.busy {
                        Button("취소") { voice.cancel() }
                            .font(.caption2)
                    }
                }

                Rectangle().fill(.white.opacity(0.13)).frame(height: 0.5)

                VStack(alignment: .leading, spacing: 6) {
                    Text("인식")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(JARVISPalette.cyan)
                    Text(voice.transcript.isEmpty
                         ? "“자비스, 안녕”이라고 말해 보세요."
                         : voice.transcript)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.89))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("응답")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(JARVISPalette.cyan)
                        .padding(.top, 3)
                    Text(voice.reply)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.91))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showKeyboard {
                    HStack(spacing: 7) {
                        TextField("질문을 입력하세요", text: $textCommand)
                            .font(.system(size: 13))
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.send)
                            .onSubmit { sendTyped() }
                        Button("전송") { sendTyped() }
                            .font(.caption)
                            .disabled(textCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                HStack(spacing: 16) {
                    Button {
                        showKeyboard.toggle()
                    } label: {
                        Label(showKeyboard ? "키보드 닫기" : "직접 입력", systemImage: "keyboard")
                    }
                    Spacer()
                    Button {
                        voice.stopSpeaking()
                    } label: {
                        Label("음성 중지", systemImage: "speaker.slash")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(JARVISPalette.cyan)

                Text("v0.1 · 카메라 영상은 기기 밖으로 보내지 않습니다. AI 분석·일정·날씨는 미연결.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.50))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func sendTyped() {
        let text = textCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        voice.respond(to: text)
        textCommand = ""
    }
}

#Preview {
    JARVISHomeView()
}
