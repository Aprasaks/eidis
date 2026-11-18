import SwiftUI

/// A cinema-style first screen backed by the same verified local snapshot as
/// the ordinary dashboard. Pure SwiftUI: no fake recognition or data queries.
struct JarvisImmersiveHomeView: View {
    let snapshot: JarvisSystemSnapshot
    let onShowDashboard: () -> Void
    let onRefresh: () -> Void
    let onOpenWork: () -> Void
    let onOpenSpeech: () -> Void
    let onOpenScreen: () -> Void
    let onOpenDiagnostics: () -> Void

    private let black = Color(red: 0.007, green: 0.012, blue: 0.021)
    private let cyan = Color(red: 0.24, green: 0.80, blue: 0.90)
    private let gray = Color(red: 0.58, green: 0.69, blue: 0.76)

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 880
            let diameter: CGFloat = compact ? 225 : min(355, geometry.size.height * 0.48)
            ZStack {
                black
                RadialGradient(
                    colors: [
                        Color(red: 0.025, green: 0.092, blue: 0.15).opacity(0.55),
                        .clear
                    ],
                    center: .init(x: 0.50, y: 0.49),
                    startRadius: 20, endRadius: max(geometry.size.width * 0.46, 360)
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, compact ? 20 : 36)
                        .padding(.top, 22)

                    Spacer(minLength: 10)

                    HStack(alignment: .center, spacing: compact ? 10 : 26) {
                        statusColumn
                            .frame(width: compact ? 168 : 226)
                        Spacer(minLength: 0)
                        centralCore(diameter: diameter)
                            .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                        nextTaskColumn
                            .frame(width: compact ? 182 : 255)
                    }
                    .padding(.horizontal, compact ? 16 : 33)

                    Spacer(minLength: 12)

                    quickActions
                        .padding(.horizontal, compact ? 20 : 36)
                        .padding(.bottom, compact ? 15 : 27)
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityLabel("JARVIS 시네마틱 홈. \(snapshot.summaryLabel)")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("JARVIS")
                    .font(.system(size: 29, weight: .ultraLight, design: .rounded))
                    .tracking(8)
                Text("PERSONAL AI SYSTEM  /  LOCAL")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(gray)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Circle()
                    .fill(snapshot.server == .online ? cyan : gray)
                    .frame(width: 6, height: 6)
                Text(snapshot.server == .online ? "LOCAL ONLINE" :
                     snapshot.server == .checking ? "CHECKING" : "OFFLINE")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(snapshot.server == .online ? cyan : gray)
            }
            .accessibilityLabel("서버 \(snapshot.server.label)")
            Button(action: onRefresh) {
                Label("상태 새로고침", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("로컬 서버와 작업 기록 새로고침")
            Button(action: onShowDashboard) {
                Label("대시보드", systemImage: "square.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.065),
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.12), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("정보 대시보드 보기")
        }
    }

    private func indicator(_ label: String, _ value: String, verified: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(verified ? cyan.opacity(0.83) : gray.opacity(0.35))
                .frame(width: 2, height: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(gray)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(verified ? .white : gray)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("SYSTEM TELEMETRY")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(cyan)
            indicator("SERVER", snapshot.server.label,
                      verified: snapshot.server == .online)
            indicator("MEMORY", snapshot.memoryLabel,
                      verified: snapshot.recordsLoaded)
            indicator("VOICE OUTPUT", snapshot.voiceLabel,
                      verified: snapshot.voiceOutputAvailable)
            indicator("LOCAL MODEL",
                      snapshot.appleModelState.contains("사용 가능") ? "기기 내 모델 사용 가능" : "확인 필요",
                      verified: snapshot.appleModelState.contains("사용 가능"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func centralCore(diameter: CGFloat) -> some View {
        VStack(spacing: 9) {
            Text("CORE  /  01")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2.8)
                .foregroundStyle(cyan.opacity(0.8))

            JarvisCoreView(online: snapshot.server == .online,
                           diameter: diameter)
                .frame(width: diameter * 1.22, height: diameter * 1.22)
                .accessibilityLabel("동작 중인 JARVIS 광학 코어")

            Text(snapshot.server == .online ? "시스템 준비됨" : "로컬 연결 확인 필요")
                .font(.system(size: 20, weight: .light))
                .tracking(1.0)
            Text("실제 음성 인식은 아래 '음성 시작'에서 직접 실행")
                .font(.system(size: 10))
                .foregroundStyle(gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var nextTaskColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NEXT ACTION")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(cyan)
            Text("다음에 확인할 작업")
                .font(.system(size: 19, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            if snapshot.recordsLoaded,
               let project = snapshot.nextTaskProject,
               let title = snapshot.nextTaskTitle {
                Text(project)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(cyan)
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(snapshot.recordsLoaded
                     ? "진행 중이거나 예정된 작업이 없습니다."
                     : "프로젝트 기록이 확인되지 않았습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)

            if snapshot.recordsLoaded {
                Text("프로젝트 \(snapshot.projectCount)개  ·  작업 \(snapshot.taskCount)건")
                    .font(.system(size: 11))
                    .foregroundStyle(gray)
                Text("예정 \(snapshot.todoCount)  /  진행 \(snapshot.doingCount)  /  완료 기록 \(snapshot.doneCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(gray)
            } else {
                Text("숫자는 서버에서 실제 기록을 읽은 뒤 표시합니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(gray)
            }

            Button(action: onOpenWork) {
                HStack {
                    Text("작업 공간으로 이동")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(12)
                .background(cyan, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(black)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(.white.opacity(0.13), lineWidth: 0.85)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickAction("음성 시작", "mic", onOpenSpeech)
            quickAction("작업 기록", "checklist", onOpenWork)
            quickAction("화면 확인", "display", onOpenScreen)
            quickAction("시스템 진단", "stethoscope", onOpenDiagnostics)
        }
    }

    private func quickAction(_ label: String, _ icon: String,
                             _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(cyan)
                Text(label).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(gray)
            }
            .padding(.horizontal, 15)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.047),
                        in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(.white.opacity(0.10), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    JarvisImmersiveHomeView(
        snapshot: .initial,
        onShowDashboard: {}, onRefresh: {},
        onOpenWork: {}, onOpenSpeech: {},
        onOpenScreen: {}, onOpenDiagnostics: {}
    )
    .frame(width: 1180, height: 700)
}
