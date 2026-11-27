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
    @State private var facebookTokenInput = ""
    @State private var threadsTokenInput = ""
    @State private var facebookSnapshot: JarvisMetaChannelSnapshot?
    @State private var threadsSnapshot: JarvisMetaChannelSnapshot?
    @State private var facebookVerifying = false
    @State private var threadsVerifying = false
    @State private var metaRefreshing = false
    @StateObject private var socialStudio = JarvisWikiSocialStudio()
    @State private var showSocialStudio = false
    @State private var instagramPosts: [JarvisSocialPost] = []
    @State private var threadsPosts: [JarvisSocialPost] = []
    @State private var facebookPosts: [JarvisSocialPost] = []
    @State private var feedLoaded = false
    @State private var feedError: String?
    @State private var lastSync: Date?
    @State private var showRawLog = false
    @State private var lastClaudeTitle: String?
    @State private var studioMode = 0
    @State private var confirmPublishNow = false
    @State private var carouselURL = ""
    @ObservedObject private var carousel = JarvisCarouselRunner.shared
    @ObservedObject private var publisher = JarvisInstagramPublisher.shared
    @ObservedObject private var growth = JarvisGrowthLog.shared
    @ObservedObject private var threadsPublisher = JarvisThreadsPublisher.shared

    private let amber = Color(red: 0.94, green: 0.67, blue: 0.30)
    private let muted = Color(red: 0.64, green: 0.66, blue: 0.68)
    private let mint = Color(red: 0.46, green: 0.84, blue: 0.69)

    private let claudeAccent = JarvisAgentID.claude.workroomAccent

    var body: some View {
        GeometryReader { geo in
            let scale = min(1.45, max(0.85, geo.size.width / 1460))
            VStack(alignment: .leading, spacing: 14) {
                header(scale)
                Rectangle().fill(LinearGradient(colors: [amber.opacity(0.6), claudeAccent.opacity(0.5), amber.opacity(0.1)],
                                                startPoint: .leading, endPoint: .trailing)).frame(height: 1)
                kpiStrip(scale)
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 14) {
                        metaCard(scale: scale)
                            .fixedSize(horizontal: false, vertical: true)
                        youtubeCard(scale: scale)
                    }
                    .frame(width: max(280, geo.size.width * 0.29))
                    if studioMode == 0 {
                        // Carousel production uses the full right side; the routine returns after.
                        VStack(spacing: 14) {
                            todayCard(scale)
                                .fixedSize(horizontal: false, vertical: true)
                            feedCard(scale)
                        }
                        .frame(width: max(260, geo.size.width * 0.27))
                        .transition(.opacity)
                    }
                    studioColumn(scale)
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
        .task {
            // Live while open: re-read every 5 minutes; stops when the room closes.
            while !Task.isCancelled {
                await refreshAll()
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
            }
        }
        .sheet(isPresented: $showSocialStudio) {
            JarvisWikiSocialStudioView(studio: socialStudio)
        }
        .sheet(isPresented: $showFacebookConnectionSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("DECHIVE.WIKI / Facebook 페이지 연결").font(.headline)
                Text("토큰 하나만 붙여넣으세요. 액세스 토큰 디버거에서 \"Extend Access Token\"으로 받은 60일 사용자 토큰을 넣으면, 이디스가 Dechive WIKI 페이지 토큰(만료 없음)을 직접 찾아 검증 후 저장합니다. 페이지 토큰을 넣어도 됩니다.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("Facebook 토큰 (60일 사용자 토큰 또는 Facebook Page Access Token)", text: $facebookTokenInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("jarvis-meta-facebook-page-token")
                Text("대상 페이지: Dechive WIKI · ID \(JarvisMetaChannels.wikiPageID) · 사용자 토큰은 저장하지 않습니다")
                    .font(.caption).foregroundStyle(.secondary)
                if facebookVerifying { ProgressView().controlSize(.small) }
                if let error = facebookSnapshot?.error { Text(error).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button("취소") { facebookTokenInput = ""; showFacebookConnectionSheet = false }
                    Spacer()
                    Button("DECHIVE.WIKI 페이지 검증 후 저장") {
                        let token = facebookTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        facebookTokenInput = ""
                        Task { await connectFacebookAnyToken(token) }
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

    // MARK: - Operations room (all values come from live APIs or the real clock)

    private static let seoul = TimeZone(identifier: "Asia/Seoul")!

    private func clock(_ date: Date, _ zone: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = TimeZone(identifier: zone)
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Next posting window: 09:00 KST (US evening) for Threads, 22:00 KST
    /// (US morning, Europe afternoon) for the Instagram carousel.
    private func nextWindow(after now: Date) -> (title: String, at: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.seoul
        let slots: [(Int, String)] = [(9, "Threads · 미국 저녁"), (22, "Instagram 캐러셀 · 미국 아침")]
        var best: (String, Date)?
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            for (hour, title) in slots {
                guard let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day), at > now else { continue }
                if best == nil || at < best!.1 { best = (title, at) }
            }
        }
        return best ?? ("Threads · 미국 저녁", now)
    }

    private func countdown(_ from: Date, _ to: Date) -> String {
        let minutes = max(0, Int(to.timeIntervalSince(from) / 60))
        return minutes >= 60 ? "\(minutes / 60)시간 \(minutes % 60)분 후" : "\(minutes)분 후"
    }

    private func header(_ scale: CGFloat) -> some View {
        let lane = agentBay.lane(.claude)
        let live = lane.state == .running
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(claudeAccent.opacity(0.35), lineWidth: 1.2)
                    .frame(width: 46 * scale, height: 46 * scale)
                    .scaleEffect(live ? 1.25 : 1)
                    .opacity(live ? 0.2 : 1)
                    .animation(live ? .easeOut(duration: 1.1).repeatForever(autoreverses: false) : .default, value: live)
                Image(systemName: "waveform.path").font(.system(size: 22 * scale, weight: .light))
                    .foregroundStyle(amber)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("SNS OPERATIONS").font(.system(size: 25 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(amber)
                HStack(spacing: 8) {
                    Circle().fill(live ? Color.green : (lane.state == .missing ? .orange : claudeAccent))
                        .frame(width: 7, height: 7)
                    Text("CLAUDE CODE 운영 중 · DECHIVE.WIKI GLOBAL / DECHIVE 국내 · 실제 API 값만 표시")
                        .font(.system(size: 11 * scale, design: .monospaced)).foregroundStyle(muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let window = nextWindow(after: context.date)
                HStack(spacing: 14 * scale) {
                    ForEach([("서울", "Asia/Seoul"), ("뉴욕", "America/New_York"), ("런던", "Europe/London")], id: \.0) { item in
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(item.0).font(.system(size: 9 * scale)).foregroundStyle(muted)
                            Text(clock(context.date, item.1))
                                .font(.system(size: 15 * scale, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
                    Rectangle().fill(amber.opacity(0.3)).frame(width: 1, height: 28 * scale)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("다음 골든타임 · " + clock(window.at, "Asia/Seoul") + " KST")
                            .font(.system(size: 9 * scale)).foregroundStyle(muted)
                        Text(window.title + " · " + countdown(context.date, window.at))
                            .font(.system(size: 12 * scale, weight: .semibold))
                            .foregroundStyle(amber)
                    }
                }
            }
            .accessibilityIdentifier("jarvis-sns-world-clock")
            Button {
                Task { await refreshAll() }
            } label: {
                Label(metaRefreshing ? "동기화 중…" : "다시 조회", systemImage: "arrow.clockwise")
                    .font(.system(size: 12 * scale))
            }
            .buttonStyle(.bordered)
            .disabled(metaRefreshing)
            .help(lastSync.map { "마지막 동기화 " + $0.formatted(date: .omitted, time: .standard) } ?? "아직 동기화 전")
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

    // MARK: Feed and KPI data

    private struct FeedItem: Identifiable {
        let id: String
        let platform: String
        let symbol: String
        let date: Date?
        let text: String
        let image: URL?
        let likes: Int?
        let comments: Int?
    }

    private static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let meta = DateFormatter()          // Meta returns e.g. 2026-11-25T14:02:11+0000
        meta.locale = Locale(identifier: "en_US_POSIX")
        meta.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return meta.date(from: raw)
    }

    private var feed: [FeedItem] {
        func items(_ posts: [JarvisSocialPost], _ platform: String, _ symbol: String) -> [FeedItem] {
            posts.map { post in
                FeedItem(id: platform + post.id, platform: platform, symbol: symbol,
                         date: Self.parseDate(post.dateText), text: post.bodyText,
                         image: post.imageURL, likes: post.like_count, comments: post.comments_count)
            }
        }
        return (items(instagramPosts, "Instagram", "camera") + items(threadsPosts, "Threads", "at") +
                items(facebookPosts, "Facebook", "f.square"))
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func isTodayKST(_ date: Date?) -> Bool {
        guard let date else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.seoul
        return calendar.isDate(date, inSameDayAs: Date())
    }

    private func relative(_ date: Date?) -> String {
        guard let date else { return "시각 미확인" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ko_KR")
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// 14일 성장 미니 그래프 (JarvisGrowthLog 실제 기록 · 기록 없는 날은 건너뜀)
    private func sparkline(_ values: [Int?], tint: Color, scale: CGFloat) -> some View {
        let points = values.enumerated().compactMap { index, value in value.map { (index, Double($0)) } }
        let low = points.map(\.1).min() ?? 0, high = points.map(\.1).max() ?? 1
        let change = points.count >= 2 ? Int(points.last!.1 - points.first!.1) : nil
        return HStack(spacing: 6) {
            GeometryReader { geo in
                if points.count >= 2 {
                    Path { path in
                        for (n, point) in points.enumerated() {
                            let x = geo.size.width * CGFloat(point.0) / CGFloat(max(1, values.count - 1))
                            let y = geo.size.height * (1 - CGFloat((point.1 - low) / max(1, high - low)))
                            n == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                } else {
                    Rectangle().fill(tint.opacity(0.25)).frame(height: 1).frame(maxHeight: .infinity)
                }
            }
            .frame(height: 16 * scale)
            Text(change.map { ($0 >= 0 ? "+" : "") + "\($0) · 14일" } ?? "기록 시작")
                .font(.system(size: 9 * scale, design: .monospaced))
                .foregroundStyle(change.map { $0 > 0 ? mint : muted } ?? muted)
                .fixedSize()
        }
    }

    private func kpiTile(_ title: String, _ value: String, _ note: String, tint: Color, scale: CGFloat,
                         trend: [Int?]? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10 * scale, design: .monospaced)).foregroundStyle(muted)
            Text(value)
                .font(.system(size: 26 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(note).font(.system(size: 9 * scale)).foregroundStyle(tint).lineLimit(1)
            if let trend { sparkline(trend, tint: tint, scale: scale) }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [tint.opacity(0.10), .black.opacity(0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.35), lineWidth: 1))
    }

    private func kpiStrip(_ scale: CGFloat) -> some View {
        let ig = model.instagramSnapshot
        let followerParts = [ig?.connected == true ? ig?.followersCount : nil,
                             threadsSnapshot?.connected == true ? threadsSnapshot?.followersCount : nil,
                             facebookSnapshot?.connected == true ? facebookSnapshot?.followersCount : nil]
        let knownFollowers = followerParts.compactMap { $0 }
        let postParts = [ig?.connected == true ? ig?.mediaCount : nil,
                         threadsSnapshot?.connected == true ? threadsSnapshot?.postsCount : nil].compactMap { $0 }
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let lastWeek = feed.filter { ($0.date ?? .distantPast) > weekAgo }.count
        let reactions = instagramPosts.reduce(0) { $0 + ($1.like_count ?? 0) + ($1.comments_count ?? 0) }
        let yt = model.youtubeSummary?.connected == true ? model.youtubeSummary?.data : nil
        return HStack(spacing: 12) {
            kpiTile("GLOBAL 팔로워", knownFollowers.isEmpty ? "—" : knownFollowers.reduce(0, +).formatted(),
                    "확인 \(knownFollowers.count)/3 채널 · IG+Threads+FB", tint: mint, scale: scale,
                    trend: growth.combined(["igFollowers", "threadsFollowers", "facebookFollowers"]))
            kpiTile("GLOBAL 게시물", postParts.isEmpty ? "—" : postParts.reduce(0, +).formatted(),
                    "Instagram + Threads", tint: amber, scale: scale,
                    trend: growth.combined(["igPosts", "threadsPosts"]))
            kpiTile("최근 7일 게시", feedLoaded ? "\(lastWeek)" : "—",
                    "최근 게시물 API 기준", tint: claudeAccent, scale: scale)
            kpiTile("IG 반응", feedLoaded && !instagramPosts.isEmpty ? reactions.formatted() : "—",
                    "최근 \(instagramPosts.count)개 좋아요+댓글", tint: .pink, scale: scale)
            kpiTile("YOUTUBE 구독자", yt?.subscriberCount ?? "—", "DECHIVE · 국내", tint: .red.opacity(0.85), scale: scale,
                    trend: growth.series("youtubeSubscribers"))
            kpiTile("YT 기간 조회수", yt?.analytics.map { $0.views.formatted() } ?? "—",
                    yt.map { $0.periodStart + " ~ " + $0.periodEnd } ?? "YouTube Analytics", tint: .red.opacity(0.85), scale: scale)
        }
        .accessibilityIdentifier("jarvis-sns-kpi-strip")
    }

    // MARK: Today's routine and published feed

    private func checklistRow(_ title: String, _ detail: String, done: Bool, scale: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 15 * scale))
                .foregroundStyle(done ? mint : muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12 * scale, weight: .medium)).foregroundStyle(.white)
                Text(detail).font(.system(size: 9 * scale)).foregroundStyle(done ? mint : muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func todayCard(_ scale: CGFloat) -> some View {
        let lane = agentBay.lane(.claude)
        let today = feed.filter { isTodayKST($0.date) }
        func posted(_ platform: String) -> FeedItem? { today.first { $0.platform == platform } }
        let claudeDone = lane.state == .completed && isTodayKST(lane.updatedAt)
        let allConnected = model.instagramSnapshot?.connected == true &&
            threadsSnapshot?.connected == true && facebookSnapshot?.connected == true
        return panel("TODAY / 오늘의 운영 루틴", symbol: "checklist", scale: scale) {
            VStack(alignment: .leading, spacing: 10 * scale) {
                checklistRow("채널 연결 점검", allConnected ? "IG · Threads · FB 모두 API 연결됨" : "연결 확인이 필요한 채널이 있습니다",
                             done: allConnected, scale: scale)
                checklistRow("Claude 현황 분석", claudeDone ? "완료 · " + (lane.updatedAt?.formatted(date: .omitted, time: .shortened) ?? "") : "SNS 현황 분석 대기",
                             done: claudeDone, scale: scale)
                checklistRow("Threads 글 게시 · 09시 골든타임",
                             posted("Threads").map { "게시됨 · " + relative($0.date) } ?? "오늘 게시 기록 없음",
                             done: posted("Threads") != nil, scale: scale)
                checklistRow("Instagram 캐러셀 · 22시 골든타임",
                             posted("Instagram").map { "게시됨 · " + relative($0.date) } ?? "오늘 게시 기록 없음",
                             done: posted("Instagram") != nil, scale: scale)
                checklistRow("Facebook 교차 게시",
                             posted("Facebook").map { "게시됨 · " + relative($0.date) } ?? "오늘 게시 기록 없음",
                             done: posted("Facebook") != nil, scale: scale)
                Text("체크는 실제 API의 게시 시각과 Claude 실행 기록으로만 표시됩니다.")
                    .font(.system(size: 9 * scale)).foregroundStyle(muted)
            }
        }
        .accessibilityIdentifier("jarvis-sns-today-routine")
    }

    private func feedCard(_ scale: CGFloat) -> some View {
        panel("PUBLISHED / 최근 게시 흐름", symbol: "list.bullet.rectangle", scale: scale) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 9 * scale) {
                    if !feedLoaded {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("게시물 API 조회 중…").foregroundStyle(muted) }
                            .font(.system(size: 11 * scale))
                    } else if feed.isEmpty {
                        Text(feedError ?? "확인된 게시물이 없습니다.")
                            .font(.system(size: 11 * scale)).foregroundStyle(muted)
                    }
                    ForEach(feed.prefix(12)) { item in
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6).fill(amber.opacity(0.08))
                                if let url = item.image {
                                    AsyncImage(url: url) { phase in
                                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                                        else { Image(systemName: item.symbol).foregroundStyle(amber.opacity(0.7)) }
                                    }
                                } else {
                                    Image(systemName: item.symbol).foregroundStyle(amber.opacity(0.7))
                                }
                            }
                            .frame(width: 46 * scale, height: 46 * scale)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(item.platform).font(.system(size: 10 * scale, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(amber)
                                    Text(relative(item.date)).font(.system(size: 9 * scale)).foregroundStyle(muted)
                                    Spacer(minLength: 0)
                                    if let likes = item.likes {
                                        Label("\(likes)", systemImage: "heart").font(.system(size: 9 * scale)).foregroundStyle(.pink)
                                    }
                                    if let comments = item.comments {
                                        Label("\(comments)", systemImage: "bubble.right").font(.system(size: 9 * scale)).foregroundStyle(mint)
                                    }
                                }
                                Text(item.text.isEmpty ? "(본문 없음)" : item.text)
                                    .font(.system(size: 11 * scale)).foregroundStyle(.white.opacity(0.88))
                                    .lineLimit(2)
                            }
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
        .accessibilityIdentifier("jarvis-sns-published-feed")
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
        return "목표: DECHIVE.WIKI(역사·과학·자연 지식 위키, 출처 검증)는 해외 영어권 팔로워만 키움(한국 유입 목표 아님). 주제 밖 해시태그·전략 제안 금지. " +
            "현황(이디스 API 확인값). 해외용 DECHIVE.WIKI: " +
            "Instagram 팔로워 \(n(ig?.followersCount)) 게시물 \(n(ig?.mediaCount)) [\(s(ig?.connected == true, ig?.error, ig?.checkedAt))], " +
            "Threads 팔로워 \(n(threadsSnapshot?.followersCount)) 게시물 \(n(threadsSnapshot?.postsCount)) [\(s(threadsSnapshot?.connected == true, threadsSnapshot?.error, threadsSnapshot?.checkedAt))], " +
            "Facebook 팔로워 \(n(facebookSnapshot?.followersCount)) [\(s(facebookSnapshot?.connected == true, facebookSnapshot?.error, facebookSnapshot?.checkedAt))]. " +
            "국내 DECHIVE YouTube 구독자 \(yt?.subscriberCount ?? "미확인") 영상 \(yt?.videoCount ?? "미확인")."
    }

    private func runClaude(_ request: String) {
        let ask = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty else { return }
        // The lane accepts at most 500 characters; keep the owner's request whole
        // and shorten the context instead.
        let request = " 요청: " + String(ask.prefix(160)) + " (한국어, 600자 이내, 짧은 목록)"
        let prompt = String(verifiedSummary().prefix(500 - request.count)) + request
        lastClaudeTitle = String(ask.prefix(40))
        agentBay.runReadOnly(.claude, prompt: prompt)
    }

    /// The final answer Claude Code streamed for the latest run, if any.
    private func latestBriefing(_ lane: JarvisAgentLane) -> String? {
        guard lane.state == .completed,
              let line = lane.logs.last(where: { $0.hasPrefix("[result] ") }) else { return nil }
        let text = String(line.dropFirst("[result] ".count))
            .components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces) != "---" }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func claudeStudio(_ scale: CGFloat) -> some View {
        let lane = agentBay.lane(.claude)
        let running = lane.state == .running
        let blocked = agentBay.isAnyRunning || agentBay.nightShiftRunning || lane.state == .missing
        let quick: [(String, String, String)] = [
            ("오늘 할 일", "sparkles", "이 수치만 근거로, 오늘 해외 영어권 팔로워를 늘리기 위해 할 일 3가지를 제안해줘."),
            ("스레드 주제", "at", "DECHIVE.WIKI 주제(역사·과학·자연)로 이번 주 영어 Threads 글 주제 5개를 추천해줘. 각 1줄."),
            ("댓글 전략", "bubble.left.and.bubble.right", "팔로워 0에서 시작하는 영어권 지식 계정이 큰 계정에 댓글을 다는 전략 3가지를 알려줘."),
            ("주간 리포트", "chart.bar.xaxis", "현재 수치로 이번 주 SNS 운영 리포트를 써줘: 현황, 잘된 점, 다음 주 목표.")
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "terminal").foregroundStyle(claudeAccent)
                Text("CLAUDE CODE / SNS STUDIO")
                    .font(.system(size: 15 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(claudeAccent)
                Spacer()
                Circle().fill(running ? Color.green : (lane.state == .failed ? .orange : claudeAccent))
                    .frame(width: 7, height: 7)
                Text(lane.stateLabel + (lane.version.isEmpty ? "" : " · " + lane.version))
                    .font(.system(size: 12 * scale, design: .monospaced))
                    .foregroundStyle(running ? .green : muted)
                    .lineLimit(1)
            }
            Rectangle().fill(claudeAccent.opacity(0.25)).frame(height: 1)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(quick, id: \.0) { item in
                    Button { runClaude(item.2) } label: {
                        Label(item.0, systemImage: item.1)
                            .font(.system(size: 12 * scale, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(item.0 == "오늘 할 일" ? claudeAccent.opacity(0.85) : claudeAccent.opacity(0.35))
                    .disabled(blocked)
                    .accessibilityIdentifier(item.0 == "오늘 할 일" ? "jarvis-sns-claude-analyze" : "jarvis-sns-claude-quick")
                }
            }
            HStack(spacing: 8) {
                TextField("Claude Code에게 SNS 질문 (예: 이 캐러셀 캡션 영어로 다듬어줘)", text: $claudeRequest)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12 * scale))
                    .onSubmit { if !blocked { runClaude(claudeRequest); claudeRequest = "" } }
                    .accessibilityIdentifier("jarvis-sns-claude-request")
                Button("보내기") { runClaude(claudeRequest); claudeRequest = "" }
                    .buttonStyle(.bordered)
                    .disabled(blocked || claudeRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("중단") { agentBay.cancel(.claude) }
                    .buttonStyle(.bordered)
                    .disabled(!running)
                    .accessibilityIdentifier("jarvis-sns-claude-stop")
            }
            Text(agentBay.nightShiftRunning ? "야간 Knowledge 근무 중에는 실행하지 않습니다." :
                 lane.state == .missing ? "Claude Code CLI를 찾지 못했습니다." :
                 "읽기 전용 · 파일 수정·게시·토큰 접근 없음 · 확인된 수치만 전달")
                .font(.system(size: 10 * scale)).foregroundStyle(muted)

            // Briefing: the final answer of the latest real run, rendered cleanly.
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("BRIEFING").font(.system(size: 10 * scale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(claudeAccent)
                    if let title = lastClaudeTitle {
                        Text("· " + title).font(.system(size: 10 * scale)).foregroundStyle(muted).lineLimit(1)
                    }
                    Spacer()
                    if let at = lane.updatedAt, lane.lastRun != nil {
                        Text(at.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10 * scale, design: .monospaced)).foregroundStyle(muted)
                    }
                    Toggle("원본 로그", isOn: $showRawLog)
                        .toggleStyle(.switch).controlSize(.mini)
                        .font(.system(size: 10 * scale))
                        .accessibilityIdentifier("jarvis-sns-claude-raw-toggle")
                }
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 8) {
                            if running {
                                HStack(spacing: 10) {
                                    ProgressView().controlSize(.small)
                                    Text("Claude Code가 채널 데이터를 분석하고 있습니다…")
                                        .foregroundStyle(claudeAccent)
                                }
                                .font(.system(size: 13 * scale, weight: .medium))
                            }
                            if showRawLog || running || lane.state == .failed {
                                ForEach(Array(lane.logs.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(size: 11 * scale, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.78))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            } else if let briefing = latestBriefing(lane) {
                                Text(markdown(briefing))
                                    .font(.system(size: 14 * scale))
                                    .lineSpacing(5)
                                    .foregroundStyle(.white.opacity(0.93))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("› 위 버튼을 누르면 Claude Code가 실제 채널 수치를 읽고 운영 브리핑을 작성합니다.")
                                    .font(.system(size: 12 * scale)).foregroundStyle(muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    .onChange(of: lane.updatedAt) { _, _ in
                        if (showRawLog || running), let last = lane.logs.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(claudeAccent.opacity(running ? 0.6 : 0.22),
                                                                  lineWidth: running ? 1.4 : 1))
                .animation(.easeInOut(duration: 0.3), value: running)
            }
            .frame(maxHeight: .infinity)
            Text("분석 결과는 제안입니다. 게시는 항상 사용자가 직접 승인합니다.")
                .font(.system(size: 11 * scale)).foregroundStyle(muted)
        }
        .padding(19)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [claudeAccent.opacity(0.08), .black.opacity(0.52)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(claudeAccent.opacity(0.50)))
        .onAppear { agentBay.probeAll() }
    }

    // MARK: - Claude studio switcher and carousel production

    private func studioColumn(_ scale: CGFloat) -> some View {
        VStack(spacing: 10) {
            Picker("", selection: $studioMode) {
                Text("분석 브리핑").tag(0)
                Text("캐러셀 제작").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("jarvis-sns-studio-mode")
            if studioMode == 0 { claudeStudio(scale) } else { carouselStudio(scale) }
        }
        .onAppear { if carousel.isRunning { studioMode = 1 } }
        .onChange(of: carousel.stage) { _, stage in
            if stage == .fetching { withAnimation { studioMode = 1 } }
        }
    }

    private func pipeline(_ scale: CGFloat) -> some View {
        let steps: [JarvisCarouselRunner.Stage] = [.fetching, .writing, .rendering, .checking, .review]
        let current = carousel.stage
        return HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let done = current != .failed && current.rawValue > step.rawValue
                let active = current == step
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(done ? mint : (active ? claudeAccent : Color.white.opacity(0.08)))
                            .frame(width: 20 * scale, height: 20 * scale)
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 10 * scale, weight: .bold)).foregroundStyle(.black)
                        } else if active && carousel.isRunning {
                            ProgressView().controlSize(.mini).tint(.black)
                        } else {
                            Text("\(index + 1)").font(.system(size: 10 * scale, weight: .bold)).foregroundStyle(active ? .black : muted)
                        }
                    }
                    Text(step.label)
                        .font(.system(size: 11 * scale, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? claudeAccent : (done ? mint : muted))
                        .lineLimit(1)
                }
                if index < steps.count - 1 {
                    Rectangle().fill(done ? mint.opacity(0.6) : Color.white.opacity(0.12)).frame(height: 1)
                }
            }
        }
        .accessibilityIdentifier("jarvis-sns-carousel-pipeline")
    }

    /// 게시 줄: 권한 상태, 22시 자동 게시 안내, 승인된 결과물만 누를 수 있는 "지금 게시", 게시 링크.
    private func publishRow(_ scale: CGFloat) -> some View {
        let status = carousel.meta?.status
        let permalink = carousel.runDirectory.flatMap { JarvisInstagramPublisher.record($0)?["permalink"] as? String }
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
        return HStack(spacing: 10) {
            Image(systemName: "paperplane")
                .foregroundStyle(publisher.permissionOK == false ? Color.orange : mint)
            Text(publisher.permissionStatus).foregroundStyle(publisher.permissionOK == false ? Color.orange : muted)
            Text("· " + threadsPublisher.permissionStatus)
                .foregroundStyle(threadsPublisher.permissionOK == false ? Color.orange : muted)
            Text("· 승인된 캐러셀은 22:00 자동 게시").foregroundStyle(muted)
            if let message = publisher.lastMessage {
                Text("· " + message).foregroundStyle(message.hasPrefix("게시 실패") ? Color.orange : mint).lineLimit(1)
            }
            Spacer()
            if publisher.publishing { ProgressView().controlSize(.small) }
            Button("📱 테스트 알림") {
                JarvisPushNotifier.shared.send(title: "EIDIS", body: "아이폰 알림 연결 확인 · SNS 작업실에서 보냄")
            }
            .buttonStyle(.plain).foregroundStyle(claudeAccent)
            .help("등록된 아이폰으로 테스트 알림을 보냅니다")
            Button("권한 확인") { Task { await publisher.checkPermission() } }
                .buttonStyle(.plain).foregroundStyle(claudeAccent)
            if status == "posted", let permalink {
                Button("인스타에서 보기") { NSWorkspace.shared.open(permalink) }
                    .buttonStyle(.bordered)
            } else {
                Button("지금 게시") { confirmPublishNow = true }
                    .buttonStyle(.borderedProminent).tint(mint.opacity(0.8))
                    .disabled(publisher.publishing || status != "approved" || publisher.permissionOK != true)
                    .help("승인된 캐러셀만 게시할 수 있습니다.")
                    .accessibilityIdentifier("jarvis-sns-publish-now")
            }
        }
        .font(.system(size: 11 * scale))
        .lineLimit(1)
        .task {
            if publisher.permissionOK == nil { await publisher.checkPermission() }
            if JarvisThreadsPublisher.shared.permissionOK == nil { await JarvisThreadsPublisher.shared.checkPermission() }
        }
        .confirmationDialog("승인된 캐러셀을 지금 Instagram에 게시할까요?", isPresented: $confirmPublishNow) {
            Button("지금 게시") {
                if let dir = carousel.runDirectory { Task { await publisher.publish(dir, trigger: "manual") } }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text((carousel.meta?.title ?? "") + " · 22시 자동 게시를 기다리지 않고 바로 올립니다.")
        }
    }

    private func carouselStudio(_ scale: CGFloat) -> some View {
        let running = carousel.isRunning
        let blocked = running || agentBay.nightShiftRunning
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "rectangle.stack").foregroundStyle(claudeAccent)
                Text("CLAUDE CODE / CAROUSEL STUDIO")
                    .font(.system(size: 15 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(claudeAccent)
                Spacer()
                Circle().fill(running ? Color.green : (carousel.stage == .failed ? .orange : claudeAccent))
                    .frame(width: 7, height: 7)
                // 아이폰에서 승인/반려되면 meta.status가 바뀐다 (JarvisSocialRemote → recordOwnerDecision).
                let ownerStatus: String? = carousel.meta?.status == "approved" ? "📱 승인됨 · 22시 게시 대기"
                    : carousel.meta?.status == "rejected" ? "📱 아이폰에서 반려됨"
                    : carousel.meta?.status == "posted" ? "✅ 인스타 게시 완료" : nil
                Text(running ? carousel.stage.label : (ownerStatus ?? carousel.stage.label))
                    .font(.system(size: 12 * scale, design: .monospaced))
                    .foregroundStyle(running ? .green : (ownerStatus != nil ? mint : muted))
            }
            Rectangle().fill(claudeAccent.opacity(0.25)).frame(height: 1)
            pipeline(scale)
            HStack(spacing: 8) {
                TextField("dechive.wiki/knowledge/… 위키 글 주소", text: $carouselURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12 * scale))
                    .accessibilityIdentifier("jarvis-sns-carousel-url")
                Button("이 글로 제작") { carousel.start(articleURL: carouselURL) }
                    .buttonStyle(.bordered)
                    .disabled(blocked || carouselURL.trimmingCharacters(in: .whitespaces).isEmpty)
                Button {
                    carousel.startNewest()
                } label: {
                    Label("최신 위키 글로 제작", systemImage: "play.fill").font(.system(size: 12 * scale, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(claudeAccent.opacity(0.85))
                .disabled(blocked)
                .accessibilityIdentifier("jarvis-sns-carousel-start")
                Button("중단") { carousel.cancel() }
                    .buttonStyle(.bordered)
                    .disabled(!running)
            }
            HStack(spacing: 10) {
                Image(systemName: "clock").foregroundStyle(muted)
                Text(carousel.scheduleStatus + " · Knowledge(00~01시) 이후 실행 · 게시는 승인 후")
                    .lineLimit(1)
                if let title = carousel.meta?.title {
                    Text("· " + title).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                Spacer()
                if let dir = carousel.runDirectory {
                    Button("작업 폴더") { NSWorkspace.shared.open(dir) }.buttonStyle(.plain).foregroundStyle(claudeAccent)
                }
            }
            .font(.system(size: 10 * scale))
            .foregroundStyle(muted)
            publishRow(scale)
            HStack(alignment: .top, spacing: 12) {
                // Live Claude stream
                VStack(alignment: .leading, spacing: 6) {
                    Text("LIVE · CLAUDE CODE").font(.system(size: 10 * scale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(claudeAccent)
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 5) {
                                if carousel.logs.isEmpty {
                                    Text("› \"최신 위키 글로 제작\"을 누르면 Claude Code가 글을 읽고 캐러셀을 쓰는 과정이 그대로 표시됩니다.")
                                        .foregroundStyle(muted)
                                }
                                ForEach(Array(carousel.logs.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .foregroundStyle(line.contains("⚠️") ? .orange : Color.white.opacity(0.86))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                                if let live = carousel.liveStatus, carousel.isRunning {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.mini)
                                        Text(live).foregroundStyle(claudeAccent)
                                    }
                                    .id("live")
                                }
                            }
                            .font(.system(size: 10.5 * scale, design: .monospaced))
                            .padding(12)
                        }
                        .onChange(of: carousel.updatedAt) { _, _ in
                            if carousel.liveStatus != nil && carousel.isRunning {
                                proxy.scrollTo("live", anchor: .bottom)
                            } else if let last = carousel.logs.indices.last {
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                            }
                        }
                    }
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(claudeAccent.opacity(running ? 0.6 : 0.22),
                                                                      lineWidth: running ? 1.4 : 1))
                }
                .frame(maxWidth: .infinity)
                // Slides appearing as Jarvis renders them
                VStack(alignment: .leading, spacing: 6) {
                    Text("SLIDES · \(carousel.slides.count)/\(max(carousel.expectedSlides, carousel.slides.count))")
                        .font(.system(size: 10 * scale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(claudeAccent)
                    ScrollView(.vertical) {
                      VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(0..<max(carousel.expectedSlides, carousel.slides.count, 0), id: \.self) { index in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04))
                                    if index < carousel.slides.count, let image = NSImage(contentsOf: carousel.slides[index]) {
                                        Image(nsImage: image).resizable().scaledToFit().padding(3)
                                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                                    } else {
                                        VStack(spacing: 4) {
                                            ProgressView().controlSize(.small)
                                            Text(String(format: "%02d", index + 1)).font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(muted)
                                        }
                                    }
                                }
                                // Explicit height: aspect-ratio cells report no height inside a
                                // lazy grid, which let the caption draw over the slides.
                                .frame(maxWidth: .infinity)
                                .frame(height: 150 * scale)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(amber.opacity(0.25)))
                            }
                        }
                        .animation(.spring(duration: 0.45), value: carousel.slides.count)
                        if let thread = carousel.threadText, !thread.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("THREADS · 09:00").font(.system(size: 9 * scale, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(claudeAccent)
                                Text(thread).font(.system(size: 10 * scale)).foregroundStyle(.white.opacity(0.85))
                                    .textSelection(.enabled)
                            }
                            .padding(.top, 8)
                        }
                        if let caption = carousel.caption {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CAPTION").font(.system(size: 9 * scale, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(claudeAccent)
                                Text(caption).font(.system(size: 10 * scale)).foregroundStyle(.white.opacity(0.85))
                                    .textSelection(.enabled)
                            }
                            .padding(.top, 8)
                        }
                      }
                      .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            Text(carousel.error ?? "Claude는 격리 폴더에서 읽기·쓰기만 합니다 · 웹·명령 실행·게시·토큰 접근 없음 · 렌더링은 이디스가 수행")
                .font(.system(size: 10 * scale))
                .foregroundStyle(carousel.error == nil ? muted : .orange)
        }
        .padding(19)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [claudeAccent.opacity(0.08), .black.opacity(0.52)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(claudeAccent.opacity(0.50)))
        .accessibilityIdentifier("jarvis-sns-carousel-studio")
    }

    private func refreshAll() async {
        guard !metaRefreshing else { return }
        metaRefreshing = true
        async let facebook = JarvisMetaChannels.scanFacebook()
        async let threads = JarvisMetaChannels.scanThreads()
        async let igPosts = JarvisMetaInstagramService.recentVerifiedPosts()
        async let thPosts = JarvisMetaChannels.recentVerifiedPosts(.threads)
        async let fbPosts = JarvisMetaChannels.recentVerifiedPosts(.facebook)
        facebookSnapshot = await facebook
        threadsSnapshot = await threads
        let results = await (igPosts, thPosts, fbPosts)
        withAnimation(.easeInOut(duration: 0.4)) {
            instagramPosts = results.0.posts ?? []
            threadsPosts = results.1.posts ?? []
            facebookPosts = results.2.posts ?? []
            feedError = [results.0.error.map { "Instagram: " + $0 }, results.1.error.map { "Threads: " + $0 },
                         results.2.error.map { "Facebook: " + $0 }].compactMap { $0 }.first
            feedLoaded = true
        }
        lastSync = Date()
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
        // 첫 조회가 끝나기 전에는 "미연결"로 오해하지 않도록 확인 중으로 표시한다.
        if checkedAt == nil, error == nil, metaRefreshing {
            return .init(label: "확인 중…", color: muted, detail: nil)
        }
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

    private func connectFacebookAnyToken(_ token: String) async {
        guard !facebookVerifying else { return }
        facebookVerifying = true
        facebookSnapshot = await JarvisMetaChannels.connectFacebookAnyToken(token)
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
        .help("\(channel.title) 프로필을 이디스 내부에서 열기")
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
