import SwiftUI
import Foundation

struct JarvisSocialPost: Identifiable, Decodable, Sendable {
    let id: String
    let caption: String?
    let text: String?
    let message: String?
    let timestamp: String?
    let created_time: String?
    let media_url: String?
    let thumbnail_url: String?
    let full_picture: String?
    let media_type: String?
    let like_count: Int?
    let comments_count: Int?
    var bodyText: String { caption ?? text ?? message ?? "" }
    var dateText: String { timestamp ?? created_time ?? "" }
    var imageURL: URL? {
        JarvisMetaChannels.safeAvatar(thumbnail_url ?? (media_type == "VIDEO" ? nil : media_url) ?? full_picture)
    }
}

struct JarvisSocialPostsResult: Sendable {
    let posts: [JarvisSocialPost]?
    let error: String?
}

struct JarvisSocialDashboardView: View {
    let channel: JarvisSocialProfile
    let close: () -> Void
    @State private var instagram: JarvisInstagramSnapshot?
    @State private var meta: JarvisMetaChannelSnapshot?
    @State private var youtube: LiveYouTubeReply?
    @State private var posts: JarvisSocialPostsResult?
    @State private var loading = true
    @State private var error: String?
    @State private var refreshedAt: Date?
    @State private var revision = UUID()
    private let amber = Color(red: 0.96, green: 0.65, blue: 0.25)
    private let mint = Color(red: 0.48, green: 0.82, blue: 0.72)
    private let muted = Color.white.opacity(0.62)

    private var avatar: URL? {
        switch channel {
        case .instagram: instagram?.avatarURL
        case .facebook, .threads: meta?.avatarURL
        case .youtube: JarvisMetaChannels.safeAvatar(youtube?.data?.thumbnailUrl)
        }
    }
    private var connected: Bool {
        switch channel {
        case .instagram: instagram?.connected == true
        case .facebook, .threads: meta?.connected == true
        case .youtube: youtube?.connected == true
        }
    }
    private var metrics: [(String, String)] {
        switch channel {
        case .instagram: [("팔로워", count(instagram?.followersCount)), ("게시물", count(instagram?.mediaCount))]
        case .facebook, .threads: [("팔로워", count(meta?.followersCount)), ("게시물", count(meta?.postsCount))]
        case .youtube: [("구독자", youtube?.data?.subscriberCount ?? "—"), ("영상", youtube?.data?.videoCount ?? "—"), ("전체 조회수", youtube?.data?.channelViews ?? "—")]
        }
    }
    private func count(_ n: Int?) -> String { n?.formatted() ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: channel == .youtube ? "play.rectangle" : "person.crop.circle")
                Text(channel.rawValue.uppercased() + " / CHANNEL INTELLIGENCE")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Spacer()
                Text(loading ? "조회 중" : connected ? "● API 확인" : "연결 확인 필요")
                    .foregroundStyle(connected ? mint : muted)
                    .font(.caption)
                Button { revision = UUID() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(loading).help("실제 데이터 새로고침")
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityIdentifier("jarvis-native-social-close")
            }.foregroundStyle(amber)
            Rectangle().fill(amber.opacity(0.25)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        AsyncImage(url: avatar) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Image(systemName: "person.crop.circle").resizable().scaledToFit().padding(10).foregroundStyle(muted) }
                        }.frame(width: 72, height: 72).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(channel.title).font(.system(size: 19, weight: .semibold))
                            Text("공식 API · 실제 계정 데이터").font(.caption).foregroundStyle(muted)
                            if let refreshedAt {
                                Text("조회 " + refreshedAt.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(mint)
                            }
                        }
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                            metricCard(metric.0, metric.1)
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(amber) }
                    if channel == .youtube {
                        if let data = youtube?.data {
                            Text("CHANNEL ANALYTICS / " + data.periodStart + " ~ " + data.periodEnd)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(amber)
                            if let a = data.analytics {
                                HStack(spacing: 10) {
                                    metricCard("조회수", a.views.formatted())
                                    metricCard("시청 시간(분)", a.estimatedMinutesWatched.formatted(.number.precision(.fractionLength(0))))
                                    metricCard("구독 증가", a.subscribersGained.formatted())
                                }
                            } else { Text(data.analyticsError ?? "분석 자료 미제공").foregroundStyle(muted) }
                        }
                        Text("RECENT VIDEOS / 최근 영상").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(amber)
                        if let videos = youtube?.data?.recentVideos {
                            if videos.isEmpty { Text("API에서 반환된 영상이 없습니다.").foregroundStyle(muted) }
                            ForEach(videos) { video in
                                HStack(spacing: 14) {
                                    AsyncImage(url: JarvisMetaChannels.safeAvatar(video.thumbnailUrl)) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() }
                                        else { Color.white.opacity(0.04) }
                                    }.frame(width: 144, height: 81).clipped().clipShape(RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(video.title).font(.system(size: 13, weight: .medium)).lineLimit(3)
                                        Text(video.publishedAt ?? "업로드 시각 미제공").font(.caption2).foregroundStyle(muted)
                                    }
                                    Spacer()
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                 .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            }
                        } else { Text(youtube?.data?.recentVideosError ?? "최근 영상 목록 미확인").font(.caption).foregroundStyle(muted) }
                    } else {
                        Text("RECENT POSTS / 최근 게시물").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(amber)
                        if let posts {
                            if let items = posts.posts {
                                if items.isEmpty { Text("API에서 반환된 게시물이 없습니다.").foregroundStyle(muted) }
                                ForEach(items) { post in postRow(post) }
                            } else { Text(posts.error ?? "게시물 조회 미확인").foregroundStyle(muted) }
                        } else { Text(loading ? "게시물 조회 중…" : "게시물 조회 미확인").foregroundStyle(muted) }
                    }
                    Text("— = API 미제공 · 통계의 기간과 조회 시각을 구분합니다.").font(.caption2).foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(Color(red: 0.035, green: 0.04, blue: 0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(amber.opacity(0.24), lineWidth: 1))
        .foregroundStyle(.white)
        .task(id: revision) { await refresh() }
        .accessibilityIdentifier("jarvis-native-social-dashboard")
    }

    private func metricCard(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(name).font(.caption).foregroundStyle(muted)
            Text(value).font(.system(size: 25, weight: .medium, design: .monospaced)).minimumScaleFactor(0.45).lineLimit(1)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
         .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
         .overlay(RoundedRectangle(cornerRadius: 8).stroke(amber.opacity(0.15)))
    }

    private func postRow(_ post: JarvisSocialPost) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let url = post.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Color.white.opacity(0.04) }
                }.frame(width: 106, height: 86).clipped().clipShape(RoundedRectangle(cornerRadius: 7))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(post.bodyText.isEmpty ? "텍스트 없는 게시물" : post.bodyText).font(.system(size: 13)).lineLimit(5).textSelection(.enabled)
                Text(post.dateText).font(.caption2).foregroundStyle(muted)
                HStack {
                    if let n = post.like_count { Label(n.formatted(), systemImage: "heart") }
                    if let n = post.comments_count { Label(n.formatted(), systemImage: "bubble") }
                }.font(.caption).foregroundStyle(mint)
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
         .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func refresh() async {
        loading = true
        error = nil
        posts = nil
        instagram = nil
        meta = nil
        youtube = nil
        defer { loading = false }
        switch channel {
        case .instagram:
            let result = await JarvisMetaInstagramService.scanSaved()
            guard !Task.isCancelled else { return }
            instagram = result
            error = result.error
            if result.connected { posts = await JarvisMetaInstagramService.recentVerifiedPosts() }
        case .facebook:
            let result = await JarvisMetaChannels.scanFacebook()
            guard !Task.isCancelled else { return }
            meta = result
            error = result.error
            if result.connected { posts = await JarvisMetaChannels.recentVerifiedPosts(.facebook) }
        case .threads:
            let result = await JarvisMetaChannels.scanThreads()
            guard !Task.isCancelled else { return }
            meta = result
            error = result.error
            if result.connected { posts = await JarvisMetaChannels.recentVerifiedPosts(.threads) }
        case .youtube:
            do {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 12
                config.timeoutIntervalForResource = 20
                let (data, response) = try await URLSession(configuration: config).data(from: URL(string: "http://127.0.0.1:8765/api/youtube/summary")!)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else { throw URLError(.badServerResponse) }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                youtube = try decoder.decode(LiveYouTubeReply.self, from: data)
                error = youtube?.error
            } catch { self.error = "YouTube 연동 자료 조회 실패" }
        }
        guard !Task.isCancelled else { return }
        refreshedAt = Date()
    }
}
