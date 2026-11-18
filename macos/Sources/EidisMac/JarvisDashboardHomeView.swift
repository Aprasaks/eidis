import SwiftUI

private enum ConsoleTheme {
    static let bg = Color(red: 0.012, green: 0.018, blue: 0.027)
    static let surface = Color(red: 0.048, green: 0.070, blue: 0.094)
    static let elevated = Color(red: 0.062, green: 0.094, blue: 0.128)
    static let accent = Color(red: 0.24, green: 0.79, blue: 0.89)
    static let gray = Color(red: 0.58, green: 0.68, blue: 0.75)
}

private struct ConsolePanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ConsoleTheme.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.11), lineWidth: 0.8)
            }
    }
}

struct JarvisDashboardHomeView: View {
    let snapshot: JarvisSystemSnapshot
    let onOpenWork: () -> Void
    let onOpenSpeech: () -> Void
    let onOpenScreen: () -> Void
    let onOpenDiagnostics: () -> Void
    let onOpenConsole: () -> Void
    let onRefresh: () -> Void
    let onPreviewVoice: () -> Void

    private func value(_ count: Int) -> String {
        snapshot.recordsLoaded ? count.formatted() : "—"
    }

    var body: some View {
        ZStack {
            ConsoleTheme.bg
            RadialGradient(
                colors: [Color(red: 0.050, green: 0.105, blue: 0.15).opacity(0.50),
                         .clear],
                center: .init(x: 0.39, y: 0.38),
                startRadius: 16,
                endRadius: 610
            )
            .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    header

                    HStack(alignment: .top, spacing: 15) {
                        corePanel
                            .frame(maxWidth: .infinity)
                        nextTaskPanel
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 305)

                    HStack(spacing: 11) {
                        metricPanel(icon: "network", title: "LOCAL SERVER",
                                    value: snapshot.server.label,
                                    secondary: "이 Mac · 127.0.0.1",
                                    active: snapshot.server == .online)
                        metricPanel(icon: "externaldrive", title: "MEMORY",
                                    value: snapshot.memoryLabel,
                                    secondary: snapshot.recordsLoaded
                                        ? "프로젝트 \(snapshot.projectCount)개 · 작업 \(snapshot.taskCount)건"
                                        : "기록 확인 후 숫자 표시",
                                    active: snapshot.recordsLoaded)
                        metricPanel(icon: "waveform", title: "KOREAN VOICE",
                                    value: snapshot.voiceLabel,
                                    secondary: "마이크 인식은 음성 탭에서 확인",
                                    active: snapshot.voiceOutputAvailable)
                        metricPanel(icon: "cpu", title: "ON-DEVICE AI",
                                    value: snapshot.appleModelState.contains("사용 가능")
                                        ? "로컬 모델 사용 가능" : "사용 상태 확인 필요",
                                    secondary: "기기 내 제안 · 외부 API 사용 안 함",
                                    active: snapshot.appleModelState.contains("사용 가능"))
                    }

                    actionBar

                    HStack(spacing: 12) {
                        Text("현재 화면은 검증된 로컬 정보와 사용자 작업 기록을 표시합니다. 저장된 작업이 실제 완료됐다는 뜻은 아닙니다.")
                            .font(.system(size: 10))
                            .foregroundStyle(ConsoleTheme.gray)
                        Spacer(minLength: 12)
                        Button("기존 자비스 콘솔 열기") { onOpenConsole() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ConsoleTheme.accent)
                        Button {
                            onRefresh()
                        } label: {
                            Label("상태 새로고침", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.83))
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 21)
                .frame(maxWidth: 1350)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .accessibilityLabel("JARVIS 개인 시스템 홈. \(snapshot.summaryLabel)")
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("JARVIS")
                        .font(.system(size: 30, weight: .ultraLight, design: .rounded))
                        .tracking(6.5)
                    Text("v3.7")
                        .font(.system(size: 10, weight: .medium,
                                      design: .monospaced))
                        .foregroundStyle(ConsoleTheme.accent)
                }
                Text("PERSONAL AI SYSTEM    /    LOCAL CONTROL CENTER")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(ConsoleTheme.gray)
            }
            Spacer(minLength: 10)
            JarvisStatusBadge(
                label: "SYSTEM",
                value: snapshot.server == .online ? "LOCAL ONLINE"
                    : snapshot.server == .checking ? "CHECKING" : "OFFLINE",
                state: snapshot.server == .online ? .verified
                    : snapshot.server == .checking ? .pending : .unavailable
            )
        }
    }

    private var corePanel: some View {
        ConsolePanel {
            ZStack {
                LinearGradient(
                    colors: [ConsoleTheme.elevated.opacity(0.55),
                             ConsoleTheme.surface],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "circle.hexagongrid")
                            .font(.system(size: 12))
                            .foregroundStyle(ConsoleTheme.accent)
                        Text("CORE INTERFACE")
                            .font(.system(size: 10, weight: .semibold,
                                          design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(ConsoleTheme.gray)
                        Spacer()
                        Text("01 / LOCAL")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(ConsoleTheme.gray)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 13)

                    Spacer(minLength: 0)
                    JarvisCoreView(online: snapshot.server == .online, diameter: 204)
                        .frame(height: 208)
                        .offset(y: -1)
                    Spacer(minLength: 0)
                    Text(snapshot.server == .online
                         ? "시스템 연결 확인" : "시스템 연결 확인 전")
                        .font(.system(size: 13, weight: .medium))
                    Text("음성 입력은 음성 탭에서 직접 시작")
                        .font(.system(size: 10))
                        .foregroundStyle(ConsoleTheme.gray)
                        .padding(.top, 5)
                        .padding(.bottom, 14)
                }
            }
        }
    }

    private var nextTaskPanel: some View {
        ConsolePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("NEXT WORKSPACE", systemImage: "square.stack.3d.up")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(ConsoleTheme.accent)
                    Spacer()
                    Text("저장된 기록 기준")
                        .font(.system(size: 10))
                        .foregroundStyle(ConsoleTheme.gray)
                }

                Text("다음 확인할 작업")
                    .font(.system(size: 21, weight: .semibold))
                if let name = snapshot.nextTaskProject,
                   let task = snapshot.nextTaskTitle,
                   snapshot.recordsLoaded {
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ConsoleTheme.accent)
                        .lineLimit(1)
                    Text(task)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 45, alignment: .topLeading)
                } else {
                    Text(snapshot.recordsLoaded
                         ? "진행 중 또는 예정된 작업이 없습니다."
                         : "로컬 프로젝트 목록을 확인하는 중입니다.")
                        .font(.system(size: 13))
                        .foregroundStyle(ConsoleTheme.gray)
                        .frame(maxWidth: .infinity, minHeight: 60,
                               alignment: .topLeading)
                }

                HStack(spacing: 8) {
                    countPill(title: "진행", value: value(snapshot.doingCount))
                    countPill(title: "예정", value: value(snapshot.todoCount))
                    countPill(title: "완료 기록", value: value(snapshot.doneCount))
                }

                Spacer(minLength: 0)

                Button(action: onOpenWork) {
                    HStack {
                        Text("작업 공간 열기")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConsoleTheme.bg)
                    .padding(.horizontal, 15)
                    .frame(height: 37)
                    .background(ConsoleTheme.accent,
                                in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
            .padding(19)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: .topLeading)
        }
    }

    private func countPill(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(ConsoleTheme.gray)
            Text(value).foregroundStyle(.white)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(ConsoleTheme.elevated, in: Capsule())
    }

    private func metricPanel(
        icon: String, title: String, value: String,
        secondary: String, active: Bool
    ) -> some View {
        ConsolePanel {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(active ? ConsoleTheme.accent : ConsoleTheme.gray)
                    Text(title)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.65)
                        .foregroundStyle(ConsoleTheme.gray)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(active ? ConsoleTheme.accent : ConsoleTheme.gray.opacity(0.55))
                        .frame(width: 5, height: 5)
                }
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(secondary)
                    .font(.system(size: 10))
                    .foregroundStyle(ConsoleTheme.gray)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 85, alignment: .topLeading)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 11) {
            quickButton(icon: "mic", label: "음성 탭", detail: "직접 시작", action: onOpenSpeech)
            quickButton(icon: "checklist", label: "작업", detail: "기록·제안", action: onOpenWork)
            quickButton(icon: "display", label: "화면", detail: "수동 캡처", action: onOpenScreen)
            quickButton(icon: "stethoscope", label: "진단", detail: "권한·연결", action: onOpenDiagnostics)
        }
    }

    private func quickButton(
        icon: String, label: String, detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(ConsoleTheme.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 12, weight: .semibold))
                    Text(detail).font(.system(size: 10))
                        .foregroundStyle(ConsoleTheme.gray)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(ConsoleTheme.gray)
            }
            .padding(.horizontal, 14)
            .frame(height: 57)
            .frame(maxWidth: .infinity)
            .background(ConsoleTheme.surface,
                        in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(.white.opacity(0.11))
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    JarvisDashboardHomeView(
        snapshot: .initial,
        onOpenWork: {}, onOpenSpeech: {}, onOpenScreen: {},
        onOpenDiagnostics: {}, onOpenConsole: {}, onRefresh: {},
        onPreviewVoice: {}
    )
    .frame(width: 1140, height: 680)
}
