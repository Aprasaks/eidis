import SwiftUI

/// SNS / YouTube workroom, a full-size layer like the DECHIVE.DEV workroom,
/// opened from the overview's "SNS / YOUTUBE" button. Every number comes from
/// a live, read-only platform API; unknown values stay "—". Tokens stay in
/// Keychain and never reach this view or the Claude Code prompt.
/// DECHIVE.WIKI (global, English) and DECHIVE (domestic, Korean) are shown apart.
struct JarvisChannelMonitorView: View {
    @ObservedObject var model: JarvisLiveDashboard
    @ObservedObject var dialogue: JarvisOverlayConversation
    @ObservedObject var agentBay: JarvisAgentTerminalBay
    let close: () -> Void
    @State private var claudeRequest = ""
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
    @State private var metaRefreshing = false
    @StateObject private var socialStudio = JarvisWikiSocialStudio()
    @State private var showSocialStudio = false

    private let amber = Color(red: 0.94, green: 0.67, blue: 0.30)
    private let muted = Color(red: 0.64, green: 0.66, blue: 0.68)
    private let mint = Color(red: 0.46, green: 0.84, blue: 0.69)

    private let claudeAccent = JarvisAgentID.claude.workroomAccent

    var body: some View {
        GeometryReader { geo in
            let scale = min(1.45, max(0.85, geo.size.width / 1460))
            VStack(alignment: .leading, spacing: 16) {
                header(scale)
                Rectangle().fill(amber.opacity(0.45)).frame(height: 1)
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 14) {
                        metaCard(scale: scale)
                            .fixedSize(horizontal: false, vertical: true)
                        youtubeCard(scale: scale)
                    }
                    .frame(width: max(300, geo.size.width * 0.38))
                    claudeStudio(scale)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.028, green: 0.034, blue: 0.040).opacity(0.98),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(amber.opacity(0.58), lineWidth: 1.2))
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("jarvis-sns-workroom")
        .task { await refreshMetaAccounts() }
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

    private func header(_ scale: CGFloat) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path").font(.system(size: 29 * scale, weight: .light))
                .foregroundStyle(amber)
            VStack(alignment: .leading, spacing: 4) {
                Text("SNS / YOUTUBE").font(.system(size: 25 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(amber)
                Text("DECHIVE.WIKI · GLOBAL   /   DECHIVE · 국내")
                    .font(.system(size: 11 * scale, design: .monospaced)).foregroundStyle(muted)
            }
            Spacer()
            Button {
                Task { await refreshMetaAccounts() }
            } label: {
                Label(metaRefreshing ? "조회 중…" : "다시 조회", systemImage: "arrow.clockwise")
                    .font(.system(size: 12 * scale))
            }
            .buttonStyle(.bordered)
            .disabled(metaRefreshing)
            .accessibilityIdentifier("jarvis-channel-monitor-refresh")
            Button(action: close) {
                Label("관제실 복귀", systemImage: "xmark")
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(amber)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityIdentifier("jarvis-sns-workroom-close")
        }
    }

    /// Verified numbers only (no tokens, no raw provider messages) for the
    /// read-only Claude Code lane. Unknown values are passed as "미확인".
    private func verifiedSummary() -> String {
        func n(_ v: Int?) -> String { v.map { String($0) } ?? "미확인" }
        func s(_ connected: Bool, _ error: String?, _ checked: Date?) -> String {
            channelState(connected: connected, error: error, checkedAt: checked).label
                .components(separatedBy: " · ").first ?? "미확인"
        }
        let ig = model.instagramSnapshot
        let yt = model.youtubeSummary?.connected == true ? model.youtubeSummary?.data : nil
        return "DECHIVE SNS 현황(자비스 API 확인값). 해외용 DECHIVE.WIKI: " +
            "Instagram 팔로워 \(n(ig?.followersCount)) 게시물 \(n(ig?.mediaCount)) [\(s(ig?.connected == true, ig?.error, ig?.checkedAt))], " +
            "Threads 팔로워 \(n(threadsSnapshot?.followersCount)) 게시물 \(n(threadsSnapshot?.postsCount)) [\(s(threadsSnapshot?.connected == true, threadsSnapshot?.error, threadsSnapshot?.checkedAt))], " +
            "Facebook [\(s(facebookSnapshot?.connected == true, facebookSnapshot?.error, facebookSnapshot?.checkedAt))]. " +
            "국내 DECHIVE YouTube 구독자 \(yt?.subscriberCount ?? "미확인") 영상 \(yt?.videoCount ?? "미확인")."
    }

    private func runClaude(_ request: String) {
        let ask = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty else { return }
        let prompt = String((verifiedSummary() + " 요청: " + ask).prefix(500))
        agentBay.runReadOnly(.claude, prompt: prompt)
    }

    private func claudeStudio(_ scale: CGFloat) -> some View {
        let lane = agentBay.lane(.claude)
        let running = lane.state == .running
        let blocked = agentBay.isAnyRunning || agentBay.nightShiftRunning || lane.state == .missing
        let defaultRequest = "이 수치만 근거로, 오늘 해외 팔로워를 늘리기 위해 할 일 3가지를 짧게 제안해줘."
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "terminal").foregroundStyle(claudeAccent)
                Text("CLAUDE CODE / SNS STUDIO")
                    .font(.system(size: 15 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(claudeAccent)
                Spacer()
                Text(lane.stateLabel + (lane.version.isEmpty ? "" : " · " + lane.version))
                    .font(.system(size: 12 * scale, design: .monospaced))
                    .foregroundStyle(running ? .green : muted)
                    .lineLimit(1)
            }
            Rectangle().fill(claudeAccent.opacity(0.25)).frame(height: 1)
            HStack(spacing: 10) {
                Button {
                    runClaude(defaultRequest)
                } label: {
                    Label("SNS 현황 분석", systemImage: "play.fill")
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(claudeAccent.opacity(0.85))
                .disabled(blocked)
                .accessibilityIdentifier("jarvis-sns-claude-analyze")
                Button("중단") { agentBay.cancel(.claude) }
                    .buttonStyle(.bordered)
                    .disabled(!running)
                    .accessibilityIdentifier("jarvis-sns-claude-stop")
                Spacer()
            }
            HStack(spacing: 8) {
                TextField("Claude Code에게 SNS 질문 (예: 이번 주 스레드 주제 추천)", text: $claudeRequest)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12 * scale))
                    .onSubmit { if !blocked { runClaude(claudeRequest); claudeRequest = "" } }
                    .accessibilityIdentifier("jarvis-sns-claude-request")
                Button("보내기") { runClaude(claudeRequest); claudeRequest = "" }
                    .buttonStyle(.bordered)
                    .disabled(blocked || claudeRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(agentBay.nightShiftRunning ? "야간 Knowledge 근무 중에는 실행하지 않습니다." :
                 lane.state == .missing ? "Claude Code CLI를 찾지 못했습니다." :
                 "읽기 전용 · 파일 수정·게시·토큰 접근 없음 · 확인된 수치만 전달")
                .font(.system(size: 10 * scale)).foregroundStyle(muted)
            Text("REAL CLI OUTPUT").font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                .foregroundStyle(claudeAccent)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        if lane.lastRun == nil || lane.logs.isEmpty {
                            Text("› SNS 현황 분석을 누르면 실제 Claude Code 출력이 표시됩니다.")
                                .foregroundStyle(muted)
                        } else {
                            ForEach(Array(lane.logs.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .foregroundStyle(Color.white.opacity(0.86))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .font(.system(size: 11 * scale, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .onChange(of: lane.updatedAt) { _, _ in
                    if let last = lane.logs.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(claudeAccent.opacity(0.22)))
            .frame(maxHeight: .infinity)
            Text("분석 결과는 제안입니다. 게시는 항상 사용자가 직접 승인합니다.")
                .font(.system(size: 11 * scale)).foregroundStyle(muted)
        }
        .padding(19)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [claudeAccent.opacity(0.065), .black.opacity(0.52)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(claudeAccent.opacity(0.50)))
        .onAppear { agentBay.probeAll() }
    }

    private func refreshMetaAccounts() async {
        guard !metaRefreshing else { return }
        metaRefreshing = true
        async let facebook = JarvisMetaChannels.scanFacebook()
        async let threads = JarvisMetaChannels.scanThreads()
        facebookSnapshot = await facebook
        threadsSnapshot = await threads
        metaRefreshing = false
    }

    /// One owner-facing state per channel. Never shows "connected" without a
    /// verified API read, and keeps expired / no-permission / outage distinct.
    private struct ChannelState {
        let label: String
        let color: Color
        let detail: String?
    }

    private func channelState(connected: Bool, error: String?, checkedAt: Date?) -> ChannelState {
        let time = checkedAt.map { " · " + $0.formatted(date: .omitted, time: .shortened) + " 확인" } ?? ""
        if connected { return .init(label: "● 연결됨" + time, color: mint, detail: nil) }
        guard let error, checkedAt != nil else {
            return .init(label: "미연결 · 토큰 연결 필요", color: muted, detail: error)
        }
        let kinds = ["인증 만료", "권한 부족", "호출 한도 초과", "Meta 서버 일시 오류", "조회 실패"]
        if let kind = kinds.first(where: { error.hasPrefix($0) }) {
            return .init(label: kind + time, color: .orange, detail: error)
        }
        if error.contains("네트워크") {
            return .init(label: "조회 불가 · 네트워크" + time, color: .orange, detail: error)
        }
        return .init(label: "확인 필요" + time, color: .orange, detail: error)
    }

    private func regionBadge(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 9 * scale, weight: .medium, design: .monospaced))
            .foregroundStyle(amber)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(amber.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(amber.opacity(0.30), lineWidth: 0.8))
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

    private func readableTime(_ raw: String?) -> String {
        guard let raw else { return "시각 미확인" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let instant = parser.date(from: raw) ?? {
            parser.formatOptions = [.withInternetDateTime]
            return parser.date(from: raw)
        }()
        guard let instant else { return "시각 미확인" }
        return instant.formatted(date: .abbreviated, time: .shortened)
    }

    private func conciseNumber(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        return value.formatted(.number.grouping(.automatic))
    }

    private func socialProfileRow(_ channel: JarvisSocialProfile, avatar: URL?,
                                  followers: Int?, posts: Int?, state: ChannelState,
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
                    Text(state.label)
                        .font(.system(size: 8 * scale))
                        .foregroundStyle(state.color)
                        .lineLimit(1)
                        .help(state.detail ?? state.label)
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
        panel("SOCIAL / DECHIVE.WIKI", symbol: "circle.hexagongrid", scale: scale) {
            VStack(alignment: .leading, spacing: 7 * scale) {
                HStack {
                    regionBadge("GLOBAL · 영어권", scale: scale)
                    Text("채널을 누르면 실제 프로필 열기")
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
                        Divider()
                        Button("Chrome 세션 확인") { Task { await dialogue.verifyChromeSession() } }
                            .accessibilityIdentifier("jarvis-meta-chrome-check")
                    } label: { Image(systemName: "gearshape").foregroundStyle(amber) }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24 * scale)
                        .help("Meta 연결 설정")
                        .accessibilityIdentifier("jarvis-social-connection-settings")
                }
                socialProfileRow(.instagram, avatar: model.instagramSnapshot?.avatarURL,
                                 followers: model.instagramSnapshot?.followersCount,
                                 posts: model.instagramSnapshot?.mediaCount,
                                 state: channelState(connected: model.instagramSnapshot?.connected == true,
                                                     error: model.instagramSnapshot?.error,
                                                     checkedAt: model.instagramSnapshot?.checkedAt),
                                 scale: scale)
                socialProfileRow(.facebook, avatar: facebookSnapshot?.avatarURL,
                                 followers: facebookSnapshot?.followersCount,
                                 posts: facebookSnapshot?.postsCount,
                                 state: channelState(connected: facebookSnapshot?.connected == true,
                                                     error: facebookSnapshot?.error,
                                                     checkedAt: facebookSnapshot?.checkedAt),
                                 scale: scale)
                socialProfileRow(.threads, avatar: threadsSnapshot?.avatarURL,
                                 followers: threadsSnapshot?.followersCount,
                                 posts: threadsSnapshot?.postsCount,
                                 state: channelState(connected: threadsSnapshot?.connected == true,
                                                     error: threadsSnapshot?.error,
                                                     checkedAt: threadsSnapshot?.checkedAt),
                                 scale: scale)
                HStack(spacing: 8) {
                    Image(systemName: "megaphone")
                        .foregroundStyle(amber.opacity(0.7))
                    Text("광고 집행 · 미연결 (Meta Ads API)")
                        .foregroundStyle(muted)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Button("초안 작업") { showSocialStudio = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(amber)
                        .accessibilityIdentifier("jarvis-meta-content-studio")
                }
                .font(.system(size: 10 * scale))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func youtubeCard(scale: CGFloat) -> some View {
        panel("YOUTUBE / CHANNEL INTELLIGENCE", symbol: "play.rectangle", scale: scale) {
            VStack(alignment: .leading, spacing: 7 * scale) {
                regionBadge("DECHIVE · 국내 · 한국어", scale: scale)
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
                                Text("연결된 채널")
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
                    Text("YouTube API · 최근 확인 " + readableTime(item.checkedAt))
                        .font(.system(size: 9 * scale)).foregroundStyle(mint)
                        .lineLimit(1)
                    Rectangle().fill(amber.opacity(0.17)).frame(height: 1)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 8 * scale) {
                            if let analytics = item.analytics {
                                Text("ANALYTICS / " + item.periodStart + " ~ " + item.periodEnd)
                                    .font(.system(size: 9 * scale, design: .monospaced))
                                    .foregroundStyle(amber)
                                HStack(spacing: 12 * scale) {
                                    labelValue("기간 조회수", analytics.views.formatted(), scale: scale)
                                    labelValue("구독자 증가", analytics.subscribersGained.formatted(), scale: scale)
                                    labelValue("시청시간", String(format: "%.1f시간",
                                        analytics.estimatedMinutesWatched / 60), scale: scale)
                                }
                            } else {
                                Text("YouTube Analytics: " + (item.analyticsError ?? "분석 정보 확인 불가"))
                                    .font(.system(size: 9 * scale))
                                    .foregroundStyle(muted)
                                    .lineLimit(2)
                            }
                            Rectangle().fill(amber.opacity(0.17)).frame(height: 1)
                            Text("최근 업로드")
                                .font(.system(size: 10 * scale, weight: .medium))
                                .foregroundStyle(amber)
                            if let videos = item.recentVideos, !videos.isEmpty {
                                ForEach(videos.prefix(5)) { video in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(video.title)
                                            .font(.system(size: 10 * scale))
                                            .foregroundStyle(.white.opacity(0.9))
                                            .lineLimit(2)
                                        Text(readableTime(video.publishedAt))
                                            .font(.system(size: 9 * scale, design: .monospaced))
                                            .foregroundStyle(muted)
                                    }
                                }
                            } else {
                                Text(item.recentVideosError ?? "최근 영상 자료 확인 불가")
                                    .font(.system(size: 9 * scale)).foregroundStyle(muted)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                    .scrollIndicators(.visible)
                    .accessibilityIdentifier("jarvis-workroom-youtube-recent-and-analytics")
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
        .background(
            LinearGradient(
                colors: [Color(red: 0.085, green: 0.068, blue: 0.042).opacity(0.71),
                         Color.black.opacity(0.60)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            LinearGradient(colors: [amber.opacity(0.44), amber.opacity(0.12), amber.opacity(0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9))
        .clipped()
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
}
