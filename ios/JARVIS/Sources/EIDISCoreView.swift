import SwiftUI

/// Pure SwiftUI, realtime-rendered optical core. Not a prerecorded GIF or video.
/// Runs slowly while foregrounded, reacts to the user's explicit mic state,
/// and respects Reduce Motion and background transitions.
struct EIDISCoreView: View {
    let listening: Bool
    let cameraLive: Bool
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    private let cyan = Color(red: 0.28, green: 0.83, blue: 0.96)
    private let blue = Color(red: 0.12, green: 0.38, blue: 0.73)
    private let violet = Color(red: 0.24, green: 0.26, blue: 0.51)

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width * 0.77, proxy.size.height * 0.92)
            ZStack {
                // Wide, subtle base halo. Never covers camera footage entirely.
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            blue.opacity(listening ? 0.28 : 0.17),
                            violet.opacity(0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: size * 0.62
                    ))
                    .frame(width: size * 1.5, height: size * 1.5)
                    .blur(radius: 13)

                Circle()
                    .stroke(cyan.opacity(0.13), lineWidth: 0.6)
                    .frame(width: size * 0.96, height: size * 0.96)

                Circle()
                    .trim(from: 0.03, to: 0.25)
                    .stroke(AngularGradient(
                        colors: [cyan.opacity(0.06), cyan.opacity(0.92), .white.opacity(0.86)],
                        center: .center
                    ), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(rotating ? 360 : 0))
                    .animation(animation(duration: listening ? 4.5 : 18), value: rotating)

                Circle()
                    .trim(from: 0.41, to: 0.65)
                    .stroke(blue.opacity(0.74),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: size * 0.91, height: size * 0.91)
                    .rotationEffect(.degrees(rotating ? -360 : 0))
                    .animation(animation(duration: listening ? 7 : 25), value: rotating)

                Circle()
                    .trim(from: 0.07, to: 0.82)
                    .stroke(cyan.opacity(0.15),
                            style: StrokeStyle(lineWidth: 0.8, dash: [2.5, 9]))
                    .frame(width: size * 0.81, height: size * 0.81)
                    .rotationEffect(.degrees(rotating ? 360 : 0))
                    .animation(animation(duration: 36), value: rotating)

                Circle()
                    .fill(RadialGradient(
                        stops: [
                            .init(color: .white.opacity(listening ? 0.92 : 0.79), location: 0),
                            .init(color: cyan.opacity(0.82), location: 0.11),
                            .init(color: blue.opacity(0.55), location: 0.31),
                            .init(color: violet.opacity(0.34), location: 0.53),
                            .init(color: .clear, location: 0.85)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.38
                    ))
                    .frame(width: size * 0.74, height: size * 0.74)
                    .blur(radius: listening ? 1 : 3)

                Circle()
                    .stroke(.white.opacity(0.17), lineWidth: 0.7)
                    .frame(width: size * 0.43, height: size * 0.43)

                HStack(spacing: 3) {
                    ForEach(0..<9, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(listening ? 0.91 : 0.40))
                            .frame(width: 2, height: CGFloat(
                                listening ? [4, 8, 14, 20, 28, 20, 14, 8, 4][index]
                                          : [3, 5, 7, 8, 11, 8, 7, 5, 3][index]
                            ))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .opacity(cameraLive ? 0.80 : 1.0)
        .accessibilityLabel(listening
            ? "EIDIS 코어 활성화, 음성 듣는 중"
            : "EIDIS 코어 대기 중")
        .onAppear { rotating = active && !reduceMotion }
        .onChange(of: active) { _, isActive in
            rotating = isActive && !reduceMotion
        }
        .onChange(of: reduceMotion) { _, reduced in
            rotating = active && !reduced
        }
    }

    private func animation(duration: Double) -> Animation? {
        guard !reduceMotion && active else { return nil }
        return .linear(duration: duration).repeatForever(autoreverses: false)
    }
}

#Preview {
    EIDISCoreView(listening: false, cameraLive: false, active: true)
        .frame(width: 360, height: 240)
        .background(.black)
}
