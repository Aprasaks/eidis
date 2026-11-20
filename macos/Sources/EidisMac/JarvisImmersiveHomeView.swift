import SwiftUI

/// Voice-first main surface: the 3D core is always visible; no fake listening state.
struct JarvisImmersiveHomeView: View {
    let snapshot: JarvisSystemSnapshot
    let onShowDashboard: () -> Void
    let onRefresh: () -> Void
    let onOpenWork: () -> Void
    let onOpenSpeech: () -> Void
    let onOpenScreen: () -> Void
    let onOpenDiagnostics: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    private let gold = Color(red: 1.0, green: 0.62, blue: 0.22)
    private let background = Color(red: 0.008, green: 0.012, blue: 0.021)

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width * 0.65, geometry.size.height * 0.72, 660)
            ZStack {
                background
                RadialGradient(colors: [gold.opacity(0.065), .clear],
                               center: .center, startRadius: 10, endRadius: diameter * 0.9)
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    HStack {
                        Text("DECHIVE")
                            .font(.system(size: 16, weight: .light, design: .rounded))
                            .tracking(5)
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Circle()
                            .fill(snapshot.server == .online ? Color.cyan : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(snapshot.server == .online ? "LOCAL ONLINE" : snapshot.server.label)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 23)

                    Spacer(minLength: 0)
                    JarvisHologramView(animated: !reduceMotion && phase == .active)
                        .frame(width: diameter, height: diameter)
                        .accessibilityLabel("천천히 회전하는 DECHIVE 3D 홀로그램 코어")
                    Text("DECHIVE")
                        .font(.system(size: 27, weight: .ultraLight, design: .rounded))
                        .tracking(11)
                        .foregroundStyle(.white.opacity(0.88))
                    Text(snapshot.server == .online ? "대기 중 · 음성 입력은 직접 시작" : "로컬 연결 확인 필요")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.52))
                        .padding(.top, 15)
                    Button(action: onOpenSpeech) {
                        Label("음성 시작", systemImage: "mic")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(gold)
                            .padding(.horizontal, 19)
                            .padding(.vertical, 11)
                            .background(gold.opacity(0.08), in: Capsule())
                            .overlay { Capsule().stroke(gold.opacity(0.35), lineWidth: 0.8) }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 19)
                    Spacer(minLength: 6)
                    HStack(spacing: 18) {
                        Button("상태 갱신", action: onRefresh)
                        Button("상세 설정", action: onShowDashboard)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 16)
                }
            }
        }
        .accessibilityLabel("DECHIVE 음성 중심 홈. \(snapshot.summaryLabel)")
    }
}

#Preview {
    JarvisImmersiveHomeView(snapshot: .initial,
        onShowDashboard: {}, onRefresh: {}, onOpenWork: {},
        onOpenSpeech: {}, onOpenScreen: {}, onOpenDiagnostics: {})
    .frame(width: 1150, height: 720)
}
