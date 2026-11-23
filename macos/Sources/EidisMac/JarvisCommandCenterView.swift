import SwiftUI

/// Full-screen, TV-friendly JARVIS command center. The active AVPlayer is owned
/// by the parent overlay and moves to the center. This view NEVER renders
/// fake analytics; all values come from live local APIs or bounded git scans.
struct JarvisCommandCenterView: View {
    @ObservedObject var model: JarvisLiveDashboard
    @ObservedObject var dialogue: JarvisOverlayConversation
    let close: () -> Void
    @State private var showInstagramTokenSheet = false
    @State private var instagramTokenInput = ""
    @State private var instagramLoginMode = JarvisMetaInstagramService.savedMode()
    @State private var showFacebookConnectionSheet = false
    @State private var showThreadsConnectionSheet = false
    @State private var facebookPageIDInput = ""
    @State private var facebookTokenInput = ""
    @State private var threadsTokenInput = ""
    @State private var facebookSnapshot: JarvisMetaChannelSnapshot?
    @State private var threadsSnapshot: JarvisMetaChannelSnapshot?
    @State private var facebookVerifying = false
    @State private var threadsVerifying = false
    @StateObject private var telemetry = JarvisMacSampler()
    @StateObject private var socialStudio = JarvisWikiSocialStudio()
    @State private var showSocialStudio = false

    private let amber = Color(red: 0.94, green: 0.67, blue: 0.30)
    private let muted = Color(red: 0.64, green: 0.66, blue: 0.68)
    private let mint = Color(red: 0.46, green: 0.84, blue: 0.69)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            // The entire command center fits the current display without an
            // outer scrolling surface. The existing voice input stays below.
            let outer = min(32, max(12, width * 0.015))
            let inputReserve: CGFloat = 116
            let topInset: CGFloat = 12
            let usableHeight = max(0, height - inputReserve - topInset)
            let scale = min(2.0, max(0.84, min(width / 1430, height / 880)))
            let narrow = width < 1120
            let gap: CGFloat = narrow ? 10 : 16
            let innerWidth = max(0, width - 2 * outer)
            let headerHeight: CGFloat = 52
            let metricsHeight: CGFloat = 66
            let columnHeight = max(0, usableHeight - headerHeight - metricsHeight - 2 * gap)
            let centerWidth = JarvisOverviewGeometry.centerWidth(innerWidth: innerWidth, height: height)
            let leftWidth = max(0, (innerWidth - centerWidth - 2 * gap) * 0.5)
            let rightWidth = max(0, innerWidth - centerWidth - 2 * gap - leftWidth)

            VStack(spacing: gap) {
                header(scale: scale).frame(height: headerHeight)
                keyMetrics(scale: scale).frame(height: metricsHeight)
                HStack(alignment: .top, spacing: gap) {
                    leftColumn(height: columnHeight, scale: scale, compact: narrow)
                        .frame(width: leftWidth, height: columnHeight)
                    centerColumn(height: columnHeight, scale: scale)
                        .frame(width: centerWidth, height: columnHeight)
                    rightColumn(height: columnHeight, scale: scale)
                        .frame(width: rightWidth, height: columnHeight)
                }
                .frame(height: columnHeight)
            }
            .frame(width: innerWidth, height: usableHeight, alignment: .top)
            .padding(.horizontal, outer)
            .padding(.top, topInset)
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .accessibilityIdentifier("jarvis-command-center")
        }
        .task {
            telemetry.reset()
            while !Task.isCancelled {
                telemetry.sample()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .task {
            await refreshMetaAccounts()
        }
        .sheet(isPresented: $showSocialStudio) {
            JarvisWikiSocialStudioView(studio: socialStudio)
        }
        .sheet(isPresented: $showFacebookConnectionSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("DECHIVE.WIKI / Facebook 페이지 연결").font(.headline)
                Text("Meta에서 DECHIVE.WIKI Facebook 페이지 ID와 해당 페이지의 Page Access Token을 확인해 입력하세요. 개인 Facebook 사용자 토큰과 다릅니다.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("Facebook Page ID (숫자)", text: $facebookPageIDInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("jarvis-meta-facebook-page-id")
                SecureField("Facebook Page Access Token", text: $facebookTokenInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("jarvis-meta-facebook-page-token")
                if let error = facebookSnapshot?.error { Text(error).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button("취소") { facebookTokenInput = ""; showFacebookConnectionSheet = false }
                    Spacer()
                    Button("DECHIVE.WIKI 페이지 검증 후 저장") {
                        let pageID = facebookPageIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let token = facebookTokenInput
                        facebookTokenInput = ""
                        Task { await connectFacebook(pageID: pageID, token: token) }
                    }
                    .disabled(facebookTokenInput.isEmpty || facebookVerifying)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(26).frame(minWidth: 460, idealWidth: 550)
            .onDisappear { facebookTokenInput = "" }
        }
        .sheet(isPresented: $showThreadsConnectionSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("DECHIVE.WIKI / Threads 연결").font(.headline)
                Text("Threads API 권한(threads_basic)으로 발급한 Threads 사용자 토큰을 입력하세요. Facebook·Instagram 토큰을 이곳에 재사용하지 않습니다.")
                    .font(.subheadline).foregroundStyle(.secondary)
                SecureField("Threads User Access Token", text: $threadsTokenInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("jarvis-meta-threads-user-token")
                if let error = threadsSnapshot?.error { Text(error).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button("취소") { threadsTokenInput = ""; showThreadsConnectionSheet = false }
                    Spacer()
                    Button("@dechive.wiki 검증 후 저장") {
                        let token = threadsTokenInput
                        threadsTokenInput = ""
                        Task { await connectThreads(token: token) }
                    }
                    .disabled(threadsTokenInput.isEmpty || threadsVerifying)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(26).frame(minWidth: 440, idealWidth: 520)
            .onDisappear { threadsTokenInput = "" }
        }
        .sheet(isPresented: $showInstagramTokenSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("DECHIVE.WIKI Instagram 연결")
                    .font(.headline)
                Text("토큰이 발급된 로그인 방식을 선택하세요. Facebook Business 토큰과 Instagram 로그인 토큰은 API 주소와 권한이 다릅니다. 검증에 성공한 토큰만 Mac Keychain에 저장됩니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Instagram 인증 방식", selection: $instagramLoginMode) {
                    ForEach(JarvisInstagramLoginMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                SecureField("Meta 액세스 토큰", text: $instagramTokenInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("jarvis-instagram-token-secure-field")
                Text("확인 계정: @dechive.wiki · Meta Graph API 읽기 전용 호출만 수행")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("취소") {
                        instagramTokenInput = ""
                        showInstagramTokenSheet = false
                    }
                    Spacer()
                    Button("계정 확인 후 저장") {
                        let entered = instagramTokenInput
                        instagramTokenInput = ""
                        showInstagramTokenSheet = false
                        Task { await model.connectInstagram(token: entered, mode: instagramLoginMode) }
                    }
                    .disabled(instagramTokenInput.isEmpty || model.instagramIsLoading)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(26)
            .frame(minWidth: 450, idealWidth: 510)
            .onDisappear { instagramTokenInput = "" }
        }
    }

    private func leftColumn(height: CGFloat, scale: CGFloat, compact: Bool) -> some View {
        let spacing: CGFloat = compact ? 8 : 11
        let remaining = max(0, height - 2 * spacing)
        let projectHeight = remaining * 0.27
        let metaHeight = remaining * 0.46
        let youtubeHeight = remaining - projectHeight - metaHeight
        return VStack(spacing: spacing) {
            projectsCard(scale: scale).frame(height: projectHeight)
            metaCard(scale: scale).frame(height: metaHeight)
            youtubeCard(scale: scale).frame(height: youtubeHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private func centerColumn(height: CGFloat, scale: CGFloat) -> some View {
        // The rotating core is rendered once by JarvisFullscreenOverlay
        // above the black background. Keep this entire center lane transparent:
        // no box, title, toggle, terminal, or duplicate conversation text.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: height)
            .accessibilityIdentifier("jarvis-overview-core-clear-lane")
    }

    private func rightColumn(height: CGFloat, scale: CGFloat) -> some View {
        let spacing: CGFloat = 10
        let remaining = max(0, height - 2 * spacing)
        return VStack(spacing: spacing) {
            JarvisLiveDialoguePanel(dialogue: dialogue)
                .frame(height: remaining * 0.34)
            macTelemetryCard(scale: scale)
                .frame(height: remaining * 0.39)
            systemCard(scale: scale)
                .frame(height: remaining * 0.27)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private func macTelemetryCard(scale: CGFloat) -> some View {
        panel("MAC / SYSTEM TELEMETRY", symbol: "cpu", scale: scale) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 9) {
                    if let sample = telemetry.current {
                        usageRow("CPU 전체", value: sample.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "측정 중",
                                 fraction: sample.cpuPercent.map { $0 / 100 }, scale: scale)
                        usageRow("메모리 · VM 추정", value: sample.memoryBytes.map { gib($0) + " / " + gib(sample.totalMemory) } ?? "미확인",
                                 fraction: sample.memoryBytes.map { Double($0) / Double(max(1,sample.totalMemory)) }, scale: scale)
                        let available = sample.diskAvailable
                        usageRow("저장소 · 데이터 볼륨", value: available.map { gib($0) + " 여유" } ?? "미확인",
                                 fraction: sample.diskUsed.flatMap { used in available.map { Double(used) / max(1, Double(used) + Double($0)) } }, scale: scale)
                        if let used = sample.diskUsed, let total = sample.diskTotal {
                            systemRow("볼륨 사용 / 용량", gib(used) + " / " + gib(total), scale: scale)
                        }
                        systemRow("배터리", sample.batteryPercent.map { "\($0)%" } ?? "미확인", scale: scale)
                        systemRow("전원", sample.powerSource, scale: scale)
                        systemRow("열 상태", sample.thermal, scale: scale)
                        Text("Mac OS 카운터 · 3초 간격")
                            .font(.system(size: 9 * scale)).foregroundStyle(muted)
                    } else { status("Mac 시스템 값 측정 중", scale: scale) }
                }
            }.scrollIndicators(.visible)
        }
    }
    private func gib(_ bytes: UInt64) -> String {
        String(format: "%.1f GiB", Double(bytes) / 1_073_741_824)
    }
    private func usageRow(_ name: String, value: String, fraction: Double?, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            systemRow(name, value, scale: scale)
            if let fraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule().fill(fraction > 0.9 ? amber : mint)
                            .frame(width: geometry.size.width * min(1, max(0,fraction)))
                    }
                }.frame(height: 5)
            }
        }
    }

    private func header(scale: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DECHIVE / COMMAND CENTER")
                    .font(.system(size: 21 * scale, weight: .semibold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("DECHIVE · 실시간 로컬 관제 · 확인된 자료만 표시")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(muted)
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 5) {
                    Circle().fill(model.errorText == nil ? mint : amber)
                        .frame(width: 6, height: 6)
                    Text(model.errorText == nil ? "LOCAL CHECKS ONLINE" : "PARTIAL CONNECTION")
                }
                .foregroundStyle(model.errorText == nil ? mint : amber)
                .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                Text(model.refreshedAt.map { "확인: " + $0.formatted(date: .omitted, time: .standard) } ?? "조회 중")
                    .font(.system(size: 10 * scale, design: .monospaced))
                    .foregroundStyle(muted)
            }
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))
            .accessibilityIdentifier("jarvis-command-center-close")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
    }

    private func keyMetrics(scale: CGFloat) -> some View {
        HStack(spacing: 10) {
            metric("PROJECTS", value: model.projectsReady ? String(model.projects.count) : "—", scale: scale)
            metric("TASK RECORDS", value: model.projectsReady ? String(model.taskTotal) : "—", scale: scale)
            metric("LOCAL GIT", value: model.gitSnapshot.map { String($0.repositories.count) } ?? "—", scale: scale)
            metric("GITHUB", value: model.githubSnapshot.flatMap { $0.error == nil ? String($0.repositories.count) : nil } ?? "—", scale: scale)
            metric("SAVED DATA", value: model.vaultTotal.map(String.init) ?? "—", scale: scale)
        }
    }

    private func metric(_ name: String, value: String, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.system(size: 9 * scale, weight: .medium, design: .monospaced))
                .foregroundStyle(muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 23 * scale, weight: .light, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(amber.opacity(0.13)))
    }

    private func panel<Content: View>(_ title: String, symbol: String, scale: CGFloat,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(amber)
            Rectangle().fill(amber.opacity(0.22)).frame(height: 1)
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.038, green: 0.044, blue: 0.051).opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(amber.opacity(0.20), lineWidth: 1))
        .clipped()
    }

    private func projectsCard(scale: CGFloat) -> some View {
        panel("PROJECT OPERATIONS / 로컬 작업 원장", symbol: "square.stack.3d.up", scale: scale) {
            if !model.projectsReady {
                status("프로젝트 원장 연결 실패 또는 조회 중", scale: scale)
            } else {
                HStack(spacing: 8) {
                    labelValue("진행", String(model.doing), scale: scale)
                    labelValue("예정", String(model.todo), scale: scale)
                    labelValue("완료", String(model.done), scale: scale)
                    labelValue("막힘", String(model.blocked), scale: scale)
                }
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.projects) { project in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(project.name == "JARVIS eidis" ? "DECHIVE / CORE" : project.name)
                                        .font(.system(size: 12 * scale, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(project.taskCounts.done)/\(project.tasks.count)")
                                        .font(.system(size: 10 * scale, design: .monospaced))
                                        .foregroundStyle(muted)
                                }
                                progress(project.taskCounts.done, total: project.tasks.count)
                                if let next = project.nextTasks.first {
                                    Text("NEXT / \(next.title)")
                                        .font(.system(size: 10 * scale))
                                        .foregroundStyle(muted)
                                        .lineLimit(2)
                                }
                            }
                        }
                        if model.projects.isEmpty {
                            status("등록된 프로젝트 없음", scale: scale)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.visible)
            }
        }
    }

    private func gitCard(scale: CGFloat) -> some View {
        panel("GITHUB + LOCAL GIT / 전체 저장소", symbol: "chevron.left.forwardslash.chevron.right", scale: scale) {
            if let snapshot = model.gitSnapshot {
                Text("범위: \(snapshot.scannedLocations.joined(separator: ", ")) 하위 일부 폴더")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(muted)
                    .lineLimit(2)
                if snapshot.truncated {
                    Text("탐색 상한에 도달함 · 전체 목록 아님")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(amber)
                }
                if let error = snapshot.error { status(error, scale: scale) }
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 9) {
                        if let remote = model.githubSnapshot {
                            if let error = remote.error {
                                status("GitHub: " + error, scale: scale)
                            } else {
                                HStack(spacing: 6) {
                                    Text("REMOTE / GitHub API · \(remote.repositories.count)개")
                                        .foregroundStyle(mint)
                                    Spacer(minLength: 0)
                                    Text(remote.checkedAt.formatted(date: .omitted, time: .shortened))
                                        .foregroundStyle(muted)
                                }
                                .font(.system(size: 10 * scale, design: .monospaced))
                                if remote.truncated {
                                    status("표시 상한 100개 · 전체 목록 아님", scale: scale)
                                }
                                ForEach(remote.repositories) { item in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(item.fullName).foregroundStyle(.white)
                                                .lineLimit(1)
                                            Spacer(minLength: 3)
                                            Text(item.privateRepo ? "PRIVATE" : "PUBLIC")
                                                .foregroundStyle(amber)
                                        }
                                        .font(.system(size: 10 * scale, design: .monospaced))
                                        Text("기본 \(item.defaultBranch ?? "미확인") · 열린 이슈/PR \(item.openIssueOrPrCount.map(String.init) ?? "—")")
                                            .font(.system(size: 9 * scale))
                                            .foregroundStyle(muted)
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        } else {
                            status(model.githubIsLoading ? "GitHub API에서 원격 저장소를 조회 중…" : "GitHub 원격 조회 준비 중", scale: scale)
                        }
                        Rectangle().fill(amber.opacity(0.2)).frame(height: 1)
                        Text("LOCAL / 이 Mac의 Git 작업복사본")
                            .font(.system(size: 10 * scale, design: .monospaced))
                            .foregroundStyle(mint)
                        ForEach(snapshot.repositories) { repo in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(repo.name)
                                        .font(.system(size: 12 * scale, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 5)
                                    Text(repo.branch)
                                        .font(.system(size: 10 * scale, design: .monospaced))
                                        .foregroundStyle(amber)
                                        .lineLimit(1)
                                }
                                Text(repo.latestCommit)
                                    .font(.system(size: 10 * scale, design: .monospaced))
                                    .foregroundStyle(muted)
                                    .lineLimit(1)
                                Text(repo.trackedChanged.map { "추적 파일 변경 \($0)개" } ?? "변경 사항 확인 불가")
                                    .font(.system(size: 9 * scale))
                                    .foregroundStyle(mint.opacity(0.85))
                            }
                            .padding(.vertical, 3)
                        }
                        if snapshot.repositories.isEmpty { status("발견한 로컬 Git 저장소 없음", scale: scale) }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.visible)
                Text("GitHub는 로그인 계정의 API 결과, 로컬 Git은 Mac 작업복사본입니다.")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(muted)
                    .lineLimit(2)
            } else {
                status(model.gitIsLoading ? "로컬 Git 저장소를 읽는 중…" : "로컬 Git 조회 준비 중", scale: scale)
            }
        }
    }

    private func refreshMetaAccounts() async {
        async let facebook = JarvisMetaChannels.scanFacebook()
        async let threads = JarvisMetaChannels.scanThreads()
        facebookSnapshot = await facebook
        threadsSnapshot = await threads
    }

    private func connectFacebook(pageID: String, token: String) async {
        guard !facebookVerifying else { return }
        facebookVerifying = true
        facebookSnapshot = await JarvisMetaChannels.connectFacebook(pageID: pageID, token: token)
        facebookVerifying = false
        if facebookSnapshot?.connected == true { showFacebookConnectionSheet = false }
    }

    private func connectThreads(token: String) async {
        guard !threadsVerifying else { return }
        threadsVerifying = true
        threadsSnapshot = await JarvisMetaChannels.connectThreads(token: token)
        threadsVerifying = false
        if threadsSnapshot?.connected == true { showThreadsConnectionSheet = false }
    }

    private func profileAvatar(_ url: URL?, channel: JarvisSocialProfile, scale: CGFloat) -> some View {
        ZStack {
            Circle().fill(amber.opacity(0.10))
            if let url, url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().controlSize(.mini)
                    case .failure:
                        Image(systemName: "person.crop.circle")
                            .resizable().scaledToFit().padding(7)
                            .foregroundStyle(muted)
                    @unknown default:
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(muted)
                    }
                }
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable().scaledToFit().padding(7)
                    .foregroundStyle(muted)
            }
        }
        .frame(width: 40 * scale, height: 40 * scale)
        .clipShape(Circle())
        .overlay(Circle().stroke(amber.opacity(0.40), lineWidth: 1))
        .accessibilityLabel("\(channel.title) 실제 프로필 사진 또는 기본 아이콘")
    }

    private func conciseNumber(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        return value.formatted(.number.grouping(.automatic))
    }

    private func socialProfileRow(_ channel: JarvisSocialProfile, avatar: URL?,
                                  followers: Int?, posts: Int?, connected: Bool,
                                  scale: CGFloat) -> some View {
        let platform: String = switch channel {
        case .instagram: "Instagram"
        case .facebook: "Facebook"
        case .threads: "Threads"
        case .youtube: "YouTube"
        }
        let name = channel == .facebook ? "Dechive WIKI" : "@dechive.wiki"
        return Button {
            _ = dialogue.openSocialProfile(channel)
        } label: {
            HStack(spacing: 9 * scale) {
                profileAvatar(avatar, channel: channel, scale: scale)
                VStack(alignment: .leading, spacing: 3) {
                    Text(platform)
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(name)
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 3)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 10 * scale) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("팔로워").font(.system(size: 8 * scale)).foregroundStyle(muted)
                            Text(conciseNumber(followers))
                                .font(.system(size: 11 * scale, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("게시물").font(.system(size: 8 * scale)).foregroundStyle(muted)
                            Text(conciseNumber(posts))
                                .font(.system(size: 11 * scale, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
                    Text(connected ? "● API 확인" : "연결 확인 필요")
                        .font(.system(size: 8 * scale))
                        .foregroundStyle(connected ? mint : muted)
                }
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(amber)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 9 * scale)
            .padding(.vertical, 7 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.050, green: 0.055, blue: 0.06),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(amber.opacity(0.18), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(channel.title) 프로필을 자비스 내부에서 열기")
        .accessibilityIdentifier("jarvis-social-open-\(channel.rawValue)")
    }

    private func metaCard(scale: CGFloat) -> some View {
        panel("META / DECHIVE.WIKI", symbol: "person.crop.circle", scale: scale) {
            VStack(alignment: .leading, spacing: 7 * scale) {
                HStack {
                    Text("실제 계정 프로필 · 클릭하면 자비스에서 열기")
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(muted)
                    Spacer(minLength: 0)
                    Menu {
                        Button("Instagram 토큰 연결 / 교체") { showInstagramTokenSheet = true }
                            .accessibilityIdentifier("jarvis-instagram-token-connect")
                        Button("Facebook 페이지 연결 / 교체") { showFacebookConnectionSheet = true }
                            .accessibilityIdentifier("jarvis-meta-facebook-connect")
                        Button("Threads 연결 / 교체") { showThreadsConnectionSheet = true }
                            .accessibilityIdentifier("jarvis-meta-threads-connect")
                    } label: { Image(systemName: "gearshape").foregroundStyle(amber) }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24 * scale)
                        .help("Meta 연결 설정")
                        .accessibilityIdentifier("jarvis-social-connection-settings")
                }
                socialProfileRow(.instagram, avatar: model.instagramSnapshot?.avatarURL,
                                 followers: model.instagramSnapshot?.followersCount,
                                 posts: model.instagramSnapshot?.mediaCount,
                                 connected: model.instagramSnapshot?.connected == true, scale: scale)
                socialProfileRow(.facebook, avatar: facebookSnapshot?.avatarURL,
                                 followers: facebookSnapshot?.followersCount,
                                 posts: facebookSnapshot?.postsCount,
                                 connected: facebookSnapshot?.connected == true, scale: scale)
                socialProfileRow(.threads, avatar: threadsSnapshot?.avatarURL,
                                 followers: threadsSnapshot?.followersCount,
                                 posts: threadsSnapshot?.postsCount,
                                 connected: threadsSnapshot?.connected == true, scale: scale)
                Text(dialogue.chrome.connectionStatus)
                    .font(.system(size: 8 * scale))
                    .foregroundStyle(muted)
                    .lineLimit(2)
                HStack {
                    Text("— = API 미제공 · 숫자 임의 생성 없음")
                        .font(.system(size: 8 * scale)).foregroundStyle(muted)
                    Spacer(minLength: 0)
                    Button {
                        Task { await dialogue.verifyChromeSession() }
                    } label: {
                        Text(dialogue.chrome.isChecking ? "연결 확인 중" : "Chrome 세션 확인")
                    }
                    .buttonStyle(.borderless)
                    .disabled(dialogue.chrome.isChecking)
                    .font(.system(size: 9 * scale)).foregroundStyle(amber)
                    .accessibilityIdentifier("jarvis-meta-chrome-check")
                    Button("AI 콘텐츠 초안") { showSocialStudio = true }
                        .buttonStyle(.borderless)
                        .font(.system(size: 9 * scale)).foregroundStyle(amber)
                        .accessibilityIdentifier("jarvis-meta-content-studio")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func youtubeCard(scale: CGFloat) -> some View {
        panel("YOUTUBE / DECHIVE", symbol: "play.rectangle", scale: scale) {
            VStack(alignment: .leading, spacing: 7 * scale) {
                if let reply = model.youtubeSummary, reply.connected, let item = reply.data {
                    Button {
                        _ = dialogue.openSocialProfile(.youtube)
                    } label: {
                        HStack(spacing: 10 * scale) {
                            profileAvatar(JarvisMetaChannels.safeAvatar(item.thumbnailUrl),
                                          channel: .youtube, scale: scale)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.channelTitle)
                                    .font(.system(size: 12 * scale, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("실제 YouTube 채널")
                                    .font(.system(size: 9 * scale)).foregroundStyle(muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right.square").foregroundStyle(amber)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("jarvis-social-open-youtube")
                    HStack(spacing: 15 * scale) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("구독자").foregroundStyle(muted)
                            Text(item.subscriberCount ?? "—").foregroundStyle(.white).fontWeight(.semibold)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("영상").foregroundStyle(muted)
                            Text(item.videoCount ?? "—").foregroundStyle(.white).fontWeight(.semibold)
                        }
                        if let views = item.channelViews {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("전체 조회수").foregroundStyle(muted)
                                Text(views).foregroundStyle(.white).fontWeight(.semibold)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10 * scale, design: .monospaced))
                    Text("Google YouTube API · 연결 채널 데이터")
                        .font(.system(size: 9 * scale)).foregroundStyle(mint)
                } else {
                    Text(model.youtubeSummary?.error ?? "YouTube 채널 연결 필요")
                        .font(.system(size: 10 * scale)).foregroundStyle(muted)
                        .lineLimit(3)
                    Button("Google 계정 연결") { Task { await model.connectYouTube() } }
                        .buttonStyle(.bordered)
                        .disabled(model.youtubeIsConnecting)
                        .accessibilityIdentifier("jarvis-youtube-google-connect")
                    Button("인증 JSON 선택") { model.importYouTubeClient() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 9 * scale))
                        .accessibilityIdentifier("jarvis-youtube-oauth-file-import")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func knowledgeCard(scale: CGFloat) -> some View {
        panel("KNOWLEDGE / 자료·기억", symbol: "books.vertical", scale: scale) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    if let count = model.vaultTotal {
                        labelValue("활성 자료", "\(count)", scale: scale)
                        ForEach(JarvisKnowledgeVault.categoryOrder, id: \.self) { category in
                            if let total = model.vaultCounts[category], total > 0 {
                                HStack {
                                    Text(JarvisKnowledgeVault.labels[category] ?? category)
                                    Spacer()
                                    Text("\(total)")
                                }
                                .font(.system(size: 10 * scale))
                                .foregroundStyle(muted)
                            }
                        }
                        if count == 0 { status("활성 보관함이 비어 있습니다.", scale: scale) }
                    } else { status("자료 보관함 조회 안 됨", scale: scale) }
                    Divider().overlay(muted.opacity(0.25))
                    JarvisLearningReviewView(learning: dialogue.learning)
                    Text("로컬 SQLite · 외부 동기화 아님")
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.visible)
        }
    }

    private func systemCard(scale: CGFloat) -> some View {
        panel("SYSTEM / 상태", symbol: "waveform.path.ecg", scale: scale) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    systemRow("SQLite", model.databaseStatus == "ok" ? "OK" : "확인 불가", scale: scale)
                    systemRow("Ollama", model.ollamaVersion.map { "v\($0)" } ?? "연결 안 됨", scale: scale)
                    systemRow("프로필", model.profileCount.map { "\($0)건" } ?? "확인 불가", scale: scale)
                    systemRow("저장 자료", model.vaultTotal.map { "\($0)건" } ?? "미확인", scale: scale)
                    ForEach(JarvisKnowledgeVault.categoryOrder, id: \.self) { category in
                        if let count = model.vaultCounts[category], count > 0 {
                            systemRow(JarvisKnowledgeVault.labels[category] ?? category, "\(count)건", scale: scale)
                        }
                    }
                    systemRow("최근 작업 기록", model.activityChecked ? "\(model.recordedActivity.count)건" : "미확인", scale: scale)
                    Rectangle().fill(amber.opacity(0.2)).frame(height: 1)
                    if let vercel = model.vercelSnapshot {
                        if let error = vercel.error {
                            status("Vercel: " + error, scale: scale)
                        }
                        systemRow("Vercel 프로젝트", vercel.error == nil ? "\(vercel.projects.count)개" : "미확인", scale: scale)
                        if vercel.error == nil {
                            let ready = vercel.deployments.filter { $0.state == "READY" }.count
                            let failed = vercel.deployments.filter { $0.state == "ERROR" }.count
                            systemRow("최근 배포", "\(vercel.deployments.count)건 · READY \(ready) / ERROR \(failed)", scale: scale)
                            ForEach(vercel.deployments.prefix(5)) { deployment in
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(deployment.name).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(deployment.state ?? "미확인")
                                        .foregroundStyle(deployment.state == "READY" ? mint : amber)
                                }
                                .font(.system(size: 9 * scale, design: .monospaced))
                                .foregroundStyle(muted)
                            }
                            if vercel.hasMoreDeployments {
                                status("최근 목록 일부만 표시 · 전체 배포 아님", scale: scale)
                            }
                        }
                    } else {
                        status(model.vercelIsLoading ? "Vercel 프로젝트·배포 조회 중…" : "Vercel 조회 준비 중", scale: scale)
                    }
                    systemRow("로컬 갱신 주기", "약 7초", scale: scale)
                    systemRow("GitHub 원격 조회", "10분 / 캐시 재사용", scale: scale)
                    systemRow("Vercel 원격 조회", "15분 / 캐시 재사용", scale: scale)
                    Text("실제 연결 상태 · 외부 API 사용량 미측정")
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.visible)
        }
    }

    private func activityCard(scale: CGFloat) -> some View {
        panel("LIVE CHECKS / 실제 조회 로그", symbol: "terminal", scale: scale) {
            HStack(spacing: 6) {
                Circle().fill(mint).frame(width: 5, height: 5)
                Text("대시보드 표시 중 자동 갱신 · 오류도 기록")
                    .font(.system(size: 9 * scale, design: .monospaced))
                    .foregroundStyle(muted)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.sourceChecks) { check in
                        HStack(alignment: .top, spacing: 6) {
                            Text(check.at.formatted(date: .omitted, time: .standard))
                                .foregroundStyle(muted)
                            Text(check.success ? "OK" : "ERR")
                                .foregroundStyle(check.success ? mint : amber)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.source).foregroundStyle(.white.opacity(0.90))
                                Text(check.detail).foregroundStyle(muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 10 * scale, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.visible)
            .accessibilityIdentifier("jarvis-command-real-checks")
            HStack(spacing: 6) {
                Text(">")
                Text("AWAITING COMMAND")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Int(context.date.timeIntervalSince1970).isMultiple(of: 2) ? "█" : " ")
                }
            }
            .font(.system(size: 10 * scale, design: .monospaced))
            .foregroundStyle(amber)
        }
    }

    private func recordedCard(scale: CGFloat) -> some View {
        panel("RECORDED EVENTS / DECHIVE 기록 원장", symbol: "clock.arrow.circlepath", scale: scale) {
            if model.activityChecked {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.recordedActivity.prefix(10)) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(String(event.createdAt.prefix(16)))
                                    .foregroundStyle(muted)
                                Text(event.category)
                                    .foregroundStyle(mint)
                                Spacer(minLength: 3)
                                Text(event.result)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .font(.system(size: 9 * scale, design: .monospaced))
                        }
                        if model.recordedActivity.isEmpty {
                            status("아직 기록된 작업 이벤트가 없습니다.", scale: scale)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.visible)
            } else {
                status("기록 원장 연결 실패 또는 조회 중", scale: scale)
            }
            Text("표시된 날짜는 실제 기록 시각입니다. 오늘 실행한 작업이라는 뜻이 아닙니다.")
                .font(.system(size: 9 * scale))
                .foregroundStyle(muted)
                .lineLimit(2)
        }
    }

    private func progress(_ completed: Int, total: Int) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.13))
                Capsule().fill(amber)
                    .frame(width: geometry.size.width * CGFloat(completed) / CGFloat(max(1, total)))
            }
        }
        .frame(height: 5)
    }

    private func labelValue(_ name: String, _ value: String, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).foregroundStyle(muted)
                .font(.system(size: 10 * scale))
            Text(value).foregroundStyle(.white)
                .font(.system(size: 15 * scale, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func systemRow(_ name: String, _ value: String, scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(muted)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(.white).lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 11 * scale, design: .monospaced))
    }

    private func status(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 11 * scale))
            .foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
