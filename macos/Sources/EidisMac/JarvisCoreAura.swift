import SwiftUI

/// 대시보드 코어 주변의 "살아 있는" 빛 (장식이지만 실제 상태만 반영한다).
/// - 에이전트가 실제로 실행 중이면 그 에이전트 색으로 천천히 맥동하고, 코어 아래에 작업 이름을 띄운다.
///   (Claude 주황 · Gemini 하늘 · Codex 분홍, 캐러셀 제작·인스타/Threads 게시 중이면 Claude/자비스 색)
/// - 아무 것도 실행 중이 아니면 아무 것도 그리지 않는다 (기본 코어 그대로).
struct JarvisCoreAura: View {
    @ObservedObject var agentBay: JarvisAgentTerminalBay
    @ObservedObject private var carousel = JarvisCarouselRunner.shared
    @ObservedObject private var instagram = JarvisInstagramPublisher.shared
    @ObservedObject private var threads = JarvisThreadsPublisher.shared
    let size: CGFloat

    private var activity: (color: Color, label: String)? {
        if let id = JarvisAgentID.allCases.first(where: { agentBay.lane($0).state == .running }) {
            return (id.workroomAccent, id.title.uppercased() + " · 작업 중")
        }
        if agentBay.nightShiftRunning { return (JarvisAgentID.codex.workroomAccent, "CODEX · Knowledge 야간 집필") }
        if carousel.isRunning { return (JarvisAgentID.claude.workroomAccent, "CLAUDE · 캐러셀 " + carousel.stage.label) }
        if instagram.publishing { return (Color(red: 0.46, green: 0.84, blue: 0.69), "EIDIS · 인스타 게시 중") }
        if threads.publishing { return (Color(red: 0.46, green: 0.84, blue: 0.69), "EIDIS · Threads 게시 중") }
        return nil
    }

    var body: some View {
        if let activity {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let pulse = 0.5 + 0.5 * sin(t * 2 * .pi / 2.6)      // 2.6초 주기
                let spin = Angle.degrees(t.truncatingRemainder(dividingBy: 24) / 24 * 360)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [activity.color.opacity(0.10 + 0.12 * pulse), .clear],
                                             center: .center, startRadius: size * 0.18, endRadius: size * 0.62))
                    Circle()
                        .trim(from: 0, to: 0.22)
                        .stroke(activity.color.opacity(0.75), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .frame(width: size * 0.96, height: size * 0.96)
                        .rotationEffect(spin)
                        .shadow(color: activity.color.opacity(0.8), radius: 8)
                    Circle()
                        .stroke(activity.color.opacity(0.18 + 0.22 * pulse), lineWidth: 1)
                        .frame(width: size * (0.98 + 0.03 * pulse), height: size * (0.98 + 0.03 * pulse))
                    Text(activity.label)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(activity.color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .overlay(Capsule().stroke(activity.color.opacity(0.5)))
                        .offset(y: size * 0.60)
                }
                .frame(width: size * 1.3, height: size * 1.3)
            }
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityLabel(activity.label)
            .accessibilityIdentifier("jarvis-core-aura")
        }
    }
}
