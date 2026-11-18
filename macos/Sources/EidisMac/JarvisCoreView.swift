import SwiftUI

/// An actual SwiftUI-rendered optical core, not a prerendered movie/image.
/// Slow rings are visual decoration; no fake system percentages or statuses.
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
            Circle()
                .fill(RadialGradient(
                    colors: [
                        (online ? cyan : blue).opacity(0.22),
                        blue.opacity(0.09),
                        .clear
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: diameter * 0.48
                ))
                .frame(width: diameter * 1.18, height: diameter * 1.18)
                .blur(radius: 19)

            Circle()
                .stroke(cyan.opacity(online ? 0.30 : 0.15), lineWidth: 0.8)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0.01, to: 0.25)
                .stroke(
                    AngularGradient(colors: [
                        cyan.opacity(0.08), cyan.opacity(0.93),
                        .white.opacity(0.8)
                    ], center: .center),
                    style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(canAnimate
                           ? .linear(duration: 21).repeatForever(autoreverses: false)
                           : nil, value: spinning)

            Circle()
                .trim(from: 0.47, to: 0.71)
                .stroke(blue.opacity(0.72),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: diameter * 0.88, height: diameter * 0.88)
                .rotationEffect(.degrees(spinning ? -360 : 0))
                .animation(canAnimate
                           ? .linear(duration: 29).repeatForever(autoreverses: false)
                           : nil, value: spinning)

            Circle()
                .stroke(cyan.opacity(0.19),
                        style: StrokeStyle(lineWidth: 1.0, dash: [1.5, 9]))
                .frame(width: diameter * 0.77, height: diameter * 0.77)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(canAnimate
                           ? .linear(duration: 44).repeatForever(autoreverses: false)
                           : nil, value: spinning)

            Circle()
                .stroke(cyan.opacity(0.09), lineWidth: 0.8)
                .frame(width: diameter * 0.61, height: diameter * 0.61)

            // Real vector tick marks; no particles, 3D glass, fake analyses.
            Canvas { context, size in
                let radius = diameter * 0.453
                let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                for index in 0..<48 {
                    let angle = Double(index) * (2 * .pi / 48)
                    let length: CGFloat = index.isMultiple(of: 6) ? 11 : 4
                    let from = CGPoint(x: mid.x + cos(angle) * (radius - length),
                                       y: mid.y + sin(angle) * (radius - length))
                    let to = CGPoint(x: mid.x + cos(angle) * radius,
                                     y: mid.y + sin(angle) * radius)
                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)
                    context.stroke(path,
                                   with: .color(cyan.opacity(index.isMultiple(of: 6) ? 0.58 : 0.17)),
                                   lineWidth: index.isMultiple(of: 6) ? 1.25 : 0.75)
                }
            }
            .frame(width: diameter, height: diameter)

            Circle()
                .fill(RadialGradient(
                    colors: [
                        Color.white.opacity(online ? 0.83 : 0.42),
                        cyan.opacity(online ? 0.52 : 0.20),
                        blue.opacity(0.19),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.25
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
}

#Preview {
    JarvisCoreView(online: true, diameter: 285)
        .frame(width: 450, height: 420)
        .background(Color.black)
}
