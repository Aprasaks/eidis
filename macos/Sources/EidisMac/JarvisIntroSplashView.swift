import SwiftUI

/// Launch overlay observes actual verified state; it never announces a fake
/// completed step. It is dismissed by its parent after a bounded reveal period,
/// even if offline, so diagnostics remain reachable.
struct JarvisIntroSplashView: View {
    let snapshot: JarvisSystemSnapshot

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.012, green: 0.018, blue: 0.027)
                    .ignoresSafeArea()
                RadialGradient(
                    colors: [Color.cyan.opacity(0.09), .clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: min(geometry.size.width, geometry.size.height) * 0.44
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    Text("J A R V I S")
                        .font(.system(size: 34, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                        .tracking(8)
                    Text("PERSONAL AI SYSTEM")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(3.4)
                        .foregroundStyle(Color.cyan.opacity(0.62))
                        .padding(.top, 11)

                    JarvisCoreView(online: snapshot.server == .online,
                                   diameter: min(260, geometry.size.height * 0.35))
                        .padding(.top, 17)

                    VStack(spacing: 14) {
                        HStack(spacing: 9) {
                            Circle()
                                .fill(snapshot.server == .online
                                      ? Color.cyan : Color.gray)
                                .frame(width: 7, height: 7)
                            Text("LOCAL SERVER")
                                .tracking(1.7)
                                .foregroundStyle(.white.opacity(0.57))
                            Spacer(minLength: 0)
                            Text(snapshot.server.label)
                                .foregroundStyle(.white.opacity(0.87))
                        }
                        HStack(spacing: 9) {
                            Circle()
                                .fill(snapshot.recordsLoaded ? Color.cyan : Color.gray)
                                .frame(width: 7, height: 7)
                            Text("WORKSPACE MEMORY")
                                .tracking(1.7)
                                .foregroundStyle(.white.opacity(0.57))
                            Spacer(minLength: 0)
                            Text(snapshot.memoryLabel)
                                .foregroundStyle(.white.opacity(0.87))
                        }
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(maxWidth: 380)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        Color(red: 0.045, green: 0.065, blue: 0.088),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 0.7)
                    }
                    .padding(.top, 9)

                    Text("기록과 서버 상태가 확인되는 대로 표시됩니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.39))
                        .padding(.top, 17)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 30)
            }
        }
        .accessibilityLabel("DECHIVE 시작 화면. \(snapshot.summaryLabel)")
    }
}

#Preview {
    JarvisIntroSplashView(snapshot: .initial)
        .frame(width: 1000, height: 720)
}
