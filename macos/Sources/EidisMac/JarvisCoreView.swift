import SwiftUI

/// Real native optical interface, not a GIF, movie or fictitious sensor.
/// Small independent views keep compilation fast on GitHub's macOS 15 runner.
struct JarvisCoreView: View {
    let online: Bool
    var diameter: CGFloat = 260

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var spinning = false

    private let cyan = Color(red: 0.22, green: 0.82, blue: 0.91)
    private let blue = Color(red: 0.20, green: 0.44, blue: 0.78)

    private var canAnimate: Bool {
        !reduceMotion && phase == .active
    }

    var body: some View {
        ZStack {
            halo
            stationaryRings
            rotatingOuterArc
            rotatingInnerArc
            rotatingDashRing
            tickMarks
            centralLight
        }
        .frame(width: diameter * 1.22, height: diameter * 1.22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(online
            ? "자비스 광학 코어. 로컬 서버 연결 확인됨. 음성 듣는 중은 아님."
            : "자비스 광학 코어. 서버 연결 확인 전 또는 연결 실패.")
        .onAppear { spinning = canAnimate }
        .onDisappear { spinning = false }
        .onChange(of: phase) { _, next in
            spinning = next == .active && !reduceMotion
        }
        .onChange(of: reduceMotion) { _, reduced in
            spinning = !reduced && phase == .active
        }
    }

    private var halo: some View {
        Circle()
            .fill(RadialGradient(
                colors: [
                    (online ? cyan : blue).opacity(0.22),
                    blue.opacity(0.09), .clear
                ],
                center: .center, startRadius: 4, endRadius: diameter * 0.48
            ))
            .frame(width: diameter * 1.18, height: diameter * 1.18)
            .blur(radius: 19)
    }

    private var stationaryRings: some View {
        ZStack {
            Circle()
                .stroke(cyan.opacity(online ? 0.30 : 0.15), lineWidth: 0.8)
                .frame(width: diameter, height: diameter)
            Circle()
                .stroke(cyan.opacity(0.09), lineWidth: 0.8)
                .frame(width: diameter * 0.61, height: diameter * 0.61)
        }
    }

    private var rotatingOuterArc: some View {
        Circle()
            .trim(from: 0.01, to: 0.25)
            .stroke(
                AngularGradient(
                    colors: [
                        cyan.opacity(0.08), cyan.opacity(0.93),
                        Color.white.opacity(0.80)
                    ], center: .center
                ),
                style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
            )
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(spinAnimation(duration: 21), value: spinning)
    }

    private var rotatingInnerArc: some View {
        Circle()
            .trim(from: 0.47, to: 0.71)
            .stroke(blue.opacity(0.72),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: diameter * 0.88, height: diameter * 0.88)
            .rotationEffect(.degrees(spinning ? -360 : 0))
            .animation(spinAnimation(duration: 29), value: spinning)
    }

    private var rotatingDashRing: some View {
        Circle()
            .stroke(cyan.opacity(0.19),
                    style: StrokeStyle(lineWidth: 1.0, dash: [1.5, 9]))
            .frame(width: diameter * 0.77, height: diameter * 0.77)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(spinAnimation(duration: 44), value: spinning)
    }

    private var tickMarks: some View {
        Canvas { context, size in
            drawTicks(in: context, size: size)
        }
        .frame(width: diameter, height: diameter)
    }

    private func drawTicks(in context: GraphicsContext, size: CGSize) {
        let radius = diameter * 0.453
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        for index in 0..<48 {
            let angle = Double(index) * (2.0 * .pi / 48.0)
            let length: CGFloat = index.isMultiple(of: 6) ? 11 : 4
            let cosine = CGFloat(cos(angle))
            let sine = CGFloat(sin(angle))
            let from = CGPoint(
                x: mid.x + cosine * (radius - length),
                y: mid.y + sine * (radius - length)
            )
            let to = CGPoint(
                x: mid.x + cosine * radius,
                y: mid.y + sine * radius
            )
            var segment = Path()
            segment.move(to: from)
            segment.addLine(to: to)
            let strength = index.isMultiple(of: 6) ? 0.58 : 0.17
            let thickness: CGFloat = index.isMultiple(of: 6) ? 1.25 : 0.75
            context.stroke(segment, with: .color(cyan.opacity(strength)),
                           lineWidth: thickness)
        }
    }

    private var centralLight: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [
                        Color.white.opacity(online ? 0.83 : 0.42),
                        cyan.opacity(online ? 0.52 : 0.20),
                        blue.opacity(0.19), .clear
                    ],
                    center: .center, startRadius: 0, endRadius: diameter * 0.25
                ))
                .frame(width: diameter * 0.43, height: diameter * 0.43)
                .blur(radius: 2)
            Circle()
                .stroke(.white.opacity(0.21), lineWidth: 0.7)
                .frame(width: diameter * 0.26, height: diameter * 0.26)
            Image(systemName: "waveform.path")
                .font(.system(size: diameter * 0.135, weight: .ultraLight))
                .foregroundStyle(.white.opacity(online ? 0.88 : 0.52))
        }
    }

    private func spinAnimation(duration: Double) -> Animation? {
        guard canAnimate else { return nil }
        return .linear(duration: duration).repeatForever(autoreverses: false)
    }
}

#Preview {
    JarvisCoreView(online: true, diameter: 285)
        .frame(width: 450, height: 420)
        .background(Color.black)
}
