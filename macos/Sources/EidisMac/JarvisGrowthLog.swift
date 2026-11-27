import Foundation

/// 채널 성장 기록 (SNS 영역). 1시간마다 실제 API 값을 읽어 "하루 한 줄"로 저장한다.
///
/// - 저장: ~/.jarvis-lab/growth/daily.json  { "yyyyMMdd": { "igFollowers": 0, ... , "at": ISO8601 } }
/// - 그날 마지막으로 성공한 값이 남는다. 조회에 실패한 항목은 비워 두고 이전 값을 지우지 않는다.
/// - 추정·보간 없음: 기록이 없는 날은 그래프에서도 빈 날로 남는다.
@MainActor
final class JarvisGrowthLog: ObservableObject {
    static let shared = JarvisGrowthLog()

    /// 기록하는 지표 (키, 표시 이름)
    static let metrics: [(key: String, label: String)] = [
        ("igFollowers", "IG 팔로워"), ("igPosts", "IG 게시물"),
        ("threadsFollowers", "Threads 팔로워"), ("threadsPosts", "Threads 게시물"),
        ("facebookFollowers", "FB 팔로워"),
        ("youtubeSubscribers", "YT 구독자"), ("youtubeViews", "YT 총 조회수"), ("youtubeVideos", "YT 영상")
    ]

    @Published private(set) var days: [String: [String: Int]] = [:]
    @Published private(set) var lastSample: Date?
    private var task: Task<Void, Never>?

    static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".jarvis-lab/growth/daily.json")

    func start() {
        guard task == nil else { return }
        load()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
    }

    /// 최근 n일 값 (오래된 날 → 오늘). 기록 없는 날은 nil.
    func series(_ key: String, days count: Int = 14) -> [Int?] {
        let f = Self.formatter()
        return (0..<count).reversed().map { offset in
            let day = f.string(from: Date().addingTimeInterval(-Double(offset) * 86_400))
            return days[day]?[key]
        }
    }

    /// 여러 지표의 날짜별 합 (예: IG+Threads+FB 팔로워). 그날 기록된 값만 더한다.
    func combined(_ keys: [String], days count: Int = 14) -> [Int?] {
        let rows = keys.map { series($0, days: count) }
        return (0..<count).map { index in
            let values = rows.compactMap { $0[index] }
            return values.isEmpty ? nil : values.reduce(0, +)
        }
    }

    /// 오늘 값과 n일 전 기록(가장 가까운 과거 기록) 차이
    func change(_ key: String, over count: Int = 7) -> Int? {
        let values = series(key, days: count + 1)
        guard let latest = values.last ?? nil, let first = values.compactMap({ $0 }).first else { return nil }
        return latest - first
    }

    func sample() async {
        async let ig = JarvisMetaInstagramService.scanSaved()
        async let th = JarvisMetaChannels.scanThreads()
        async let fb = JarvisMetaChannels.scanFacebook()
        async let yt = Self.youtube()
        var row: [String: Int] = [:]
        let (i, t, f, y) = await (ig, th, fb, yt)
        if i.connected { row["igFollowers"] = i.followersCount; row["igPosts"] = i.mediaCount }
        if t.connected { row["threadsFollowers"] = t.followersCount; row["threadsPosts"] = t.postsCount }
        if f.connected { row["facebookFollowers"] = f.followersCount }
        y.forEach { row[$0.key] = $0.value }
        guard !row.isEmpty else { return }
        let day = Self.formatter().string(from: Date())
        var today = days[day] ?? [:]
        row.forEach { today[$0.key] = $0.value }   // 실패한 항목은 그날 이전 값 유지
        days[day] = today
        lastSample = Date()
        save()
    }

    /// 자비스 로컬 서버의 읽기 전용 YouTube 요약
    nonisolated private static func youtube() async -> [String: Int] {
        guard let url = URL(string: "http://127.0.0.1:8765/api/youtube/summary") else { return [:] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = { () -> LiveYouTubeReply? in
                  let decoder = JSONDecoder()
                  decoder.keyDecodingStrategy = .convertFromSnakeCase   // 서버는 snake_case로 응답
                  return try? decoder.decode(LiveYouTubeReply.self, from: data)
              }(),
              reply.connected, let channel = reply.data else { return [:] }
        var row: [String: Int] = [:]
        if let value = channel.subscriberCount.flatMap(Int.init) { row["youtubeSubscribers"] = value }
        if let value = channel.channelViews.flatMap(Int.init) { row["youtubeViews"] = value }
        if let value = channel.videoCount.flatMap(Int.init) { row["youtubeVideos"] = value }
        return row
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
        days = saved.mapValues { $0.compactMapValues { $0 as? Int } }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: days, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }

    nonisolated static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f
    }
}
