import Foundation
import Security

/// Only verified DECHIVE.WIKI assets. Tokens never enter the local LLM,
/// user defaults, analytics, app logs or request URLs.
struct JarvisMetaChannelSnapshot: Sendable {
    let connected: Bool
    let handle: String?
    let checkedAt: Date?
    let error: String?
    let avatarURL: URL?
    let followersCount: Int?
    let postsCount: Int?

    init(connected: Bool, handle: String?, checkedAt: Date?, error: String?,
         avatarURL: URL? = nil, followersCount: Int? = nil, postsCount: Int? = nil) {
        self.connected = connected
        self.handle = handle
        self.checkedAt = checkedAt
        self.error = error
        self.avatarURL = avatarURL
        self.followersCount = followersCount
        self.postsCount = postsCount
    }
}

enum JarvisMetaChannels {
    nonisolated private static let facebookService = "dev.dechive.eidis.meta.facebook.wiki"
    nonisolated private static let threadsService = "dev.dechive.eidis.meta.threads.wiki"
    nonisolated private static let secretAccount = "channel-token"
    nonisolated private static let pageIDPreference = "jarvis.meta.facebook.wikiPageID"

    /// Metadata only. Never include Meta's raw error message, token or trace ID.
    nonisolated static func sanitizedFailure(_ data: Data, status: Int) -> String {
        struct MetaError: Decodable {
            struct Detail: Decodable { let code: Int?; let error_subcode: Int? }
            let error: Detail?
        }
        guard let parsed = try? JSONDecoder().decode(MetaError.self, from: data.prefix(16_384)),
              let detail = parsed.error else {
            return "\(failureKind(code: nil, status: status)) · Meta API HTTP \(status)"
        }
        let code = detail.code.map { " · code \($0)" } ?? ""
        let subcode = detail.error_subcode.map { " · subcode \($0)" } ?? ""
        return "\(failureKind(code: detail.code, status: status)) · Meta API HTTP \(status)\(code)\(subcode)"
    }

    /// Owner-facing category for Meta's documented numeric error codes, so an
    /// expired token, a missing permission and a temporary outage never look alike.
    nonisolated static func failureKind(code: Int?, status: Int) -> String {
        switch code {
        case 190, 102, 463, 467: return "인증 만료 · 토큰을 다시 연결하세요"
        case 10, 200, 3, 299: return "권한 부족 · 토큰 권한을 확인하세요"
        case 4, 17, 32, 613: return "호출 한도 초과 · 잠시 후 다시 조회"
        case 1, 2: return "Meta 서버 일시 오류 · 잠시 후 다시 조회"
        default:
            if status == 401 { return "인증 만료 · 토큰을 다시 연결하세요" }
            if status == 403 { return "권한 부족 · 토큰 권한을 확인하세요" }
            if status >= 500 { return "Meta 서버 일시 오류 · 잠시 후 다시 조회" }
            return "조회 실패 · 해당 계정의 토큰·권한을 확인하세요"
        }
    }

    nonisolated private static func validToken(_ token: String) -> Bool {
        (32..<8192).contains(token.utf8.count) &&
        !token.contains(where: { $0.isWhitespace || $0.isNewline })
    }

    nonisolated private static func read(_ service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secretAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func save(_ token: String, service: String) -> Bool {
        guard validToken(token) else { return false }
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secretAccount
        ]
        let update: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let code = SecItemUpdate(key as CFDictionary, update as CFDictionary)
        if code == errSecSuccess { return true }
        guard code == errSecItemNotFound else { return false }
        var insertion = key
        insertion[kSecValueData as String] = Data(token.utf8)
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess
    }

    nonisolated private static func get(_ url: URL, token: String) async -> (Int, Data)? {
        guard validToken(token) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        do {
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse, data.count <= 100_000 else { return nil }
            return (http.statusCode, data)
        } catch { return nil }
    }

    /// Only HTTPS image links returned by a verified Meta API are rendered.
    nonisolated static func safeAvatar(_ raw: String?) -> URL? {
        guard let raw, raw.count < 2048, let url = URL(string: raw),
              url.scheme == "https", url.user == nil, url.password == nil,
              url.host?.contains(".") == true else { return nil }
        return url
    }

    private struct FacebookPublicDetails: Decodable {
        struct Picture: Decodable {
            struct ImageData: Decodable { let url: String? }
            let data: ImageData?
        }
        let picture: Picture?
        let followers_count: Int?
        let fan_count: Int?
    }

    nonisolated private static func facebookDetails(pageID: String, token: String) async -> (URL?, Int?) {
        // Stats and avatar are optional; never turn a profile-field rejection
        // into a false claim that a previously verified token is disconnected.
        for fields in ["picture.type(large){url},followers_count,fan_count", "picture.type(large){url}"] {
            var parts = URLComponents(string: "https://graph.facebook.com/v27.0/\(pageID)")!
            parts.queryItems = [URLQueryItem(name: "fields", value: fields)]
            guard let url = parts.url, let (status, data) = await get(url, token: token), status == 200,
                  let details = try? JSONDecoder().decode(FacebookPublicDetails.self, from: data) else { continue }
            return (safeAvatar(details.picture?.data?.url), details.followers_count ?? details.fan_count)
        }
        return (nil, nil)
    }

    nonisolated private static func threadsDetails(token: String) async -> URL? {
        struct ThreadsPublicDetails: Decodable { let threads_profile_picture_url: String? }
        guard let url = URL(string: "https://graph.threads.net/v1.0/me?fields=threads_profile_picture_url"),
              let (status, data) = await get(url, token: token), status == 200,
              let details = try? JSONDecoder().decode(ThreadsPublicDetails.self, from: data) else { return nil }
        return safeAvatar(details.threads_profile_picture_url)
    }

    /// Real follower total from the Threads Insights API (needs the
    /// threads_manage_insights permission). Optional: a rejected metric leaves
    /// the value unknown ("—") and never marks a verified account disconnected.
    nonisolated private static func threadsFollowers(token: String) async -> Int? {
        struct Insights: Decodable {
            struct Metric: Decodable {
                struct Total: Decodable { let value: Int? }
                let name: String
                let total_value: Total?
            }
            let data: [Metric]
        }
        guard let url = URL(string: "https://graph.threads.net/v1.0/me/threads_insights?metric=followers_count"),
              let (status, data) = await get(url, token: token), status == 200,
              let reply = try? JSONDecoder().decode(Insights.self, from: data),
              let value = reply.data.first(where: { $0.name == "followers_count" })?.total_value?.value,
              value >= 0 else { return nil }
        return value
    }

    /// Exact post count by paging the owner's own threads. Returns nil rather
    /// than a partial number if the page cap is reached or any page fails.
    nonisolated private static func threadsPostCount(token: String) async -> Int? {
        struct Page: Decodable {
            struct Item: Decodable { let id: String }
            struct Paging: Decodable { let next: String? }
            let data: [Item]
            let paging: Paging?
        }
        var next = URL(string: "https://graph.threads.net/v1.0/me/threads?fields=id&limit=100")
        var total = 0
        for _ in 0..<10 {
            guard let url = next else { return total }
            guard url.scheme == "https", url.host == "graph.threads.net",
                  let (status, data) = await get(url, token: token), status == 200,
                  let page = try? JSONDecoder().decode(Page.self, from: data) else { return nil }
            total += page.data.count
            next = page.data.isEmpty ? nil : tokenFree(page.paging?.next)
        }
        return next == nil ? total : nil
    }

    /// Meta paging links can embed the access token. Strip it so the token only
    /// ever travels in the Authorization header.
    nonisolated private static func tokenFree(_ raw: String?) -> URL? {
        guard let raw, var parts = URLComponents(string: raw) else { return nil }
        parts.queryItems = parts.queryItems?.filter { $0.name != "access_token" }
        return parts.url
    }

    nonisolated static func verifyFacebook(pageID: String, token: String) async -> JarvisMetaChannelSnapshot {
        struct Page: Decodable { let id: String; let name: String?; let username: String? }
        let checked = Date()
        guard (6...25).contains(pageID.count), pageID.allSatisfy({ $0.isNumber }),
              let url = URL(string: "https://graph.facebook.com/v27.0/me?fields=id,name,username") else {
            return .init(connected: false, handle: nil, checkedAt: checked, error: "Facebook 페이지 ID는 숫자로 입력하세요.")
        }
        guard let (status, data) = await get(url, token: token) else {
            return .init(connected: false, handle: nil, checkedAt: checked, error: "Facebook 페이지 토큰이 없거나 네트워크 조회가 실패했습니다.")
        }
        guard status == 200 else {
            return .init(connected: false, handle: nil, checkedAt: checked, error: sanitizedFailure(data, status: status))
        }
        guard let page = try? JSONDecoder().decode(Page.self, from: data),
              page.id == pageID,
              let name = page.name, !name.isEmpty else {
            return .init(connected: false, handle: nil, checkedAt: checked, error: "입력한 ID와 토큰의 Facebook 페이지가 일치하지 않습니다.")
        }
        let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let username = (page.username ?? "").lowercased()
        guard (normalized.contains("dechive") && normalized.contains("wiki")) ||
              ["dechive.wiki", "dechivewiki"].contains(username) else {
            return .init(connected: false, handle: nil, checkedAt: checked, error: "DECHIVE.WIKI Facebook 페이지가 아닌 것으로 확인됐습니다.")
        }
        let (avatar, followers) = await facebookDetails(pageID: pageID, token: token)
        return .init(connected: true, handle: name, checkedAt: checked, error: nil,
                     avatarURL: avatar, followersCount: followers)
    }

    nonisolated static func verifyThreads(token: String) async -> JarvisMetaChannelSnapshot {
        struct Profile: Decodable { let id: String; let username: String? }
        let checked = Date()
        guard let url = URL(string: "https://graph.threads.net/v1.0/me?fields=id,username") else {
            return .init(connected: false, handle: nil, checkedAt: checked, error: "Threads API URL 오류")
        }
        guard let (status, data) = await get(url, token: token) else {
            return .init(connected: false, handle: nil, checkedAt: checked, error: "Threads 토큰이 없거나 네트워크 조회가 실패했습니다.")
        }
        guard status == 200 else {
            return .init(connected: false, handle: nil, checkedAt: checked, error: sanitizedFailure(data, status: status))
        }
        guard let profile = try? JSONDecoder().decode(Profile.self, from: data),
              !profile.id.isEmpty,
              profile.username?.lowercased() == "dechive.wiki" else {
            return .init(connected: false, handle: nil, checkedAt: checked, error: "@dechive.wiki Threads 계정과 일치하지 않습니다.")
        }
        async let avatar = threadsDetails(token: token)
        async let followers = threadsFollowers(token: token)
        async let posts = threadsPostCount(token: token)
        return .init(connected: true, handle: "@dechive.wiki", checkedAt: checked, error: nil,
                     avatarURL: await avatar, followersCount: await followers, postsCount: await posts)
    }

    nonisolated static func scanFacebook() async -> JarvisMetaChannelSnapshot {
        guard let token = read(facebookService),
              let pageID = UserDefaults.standard.string(forKey: pageIDPreference) else {
            return .init(connected: false, handle: nil, checkedAt: nil, error: "Facebook 페이지 ID 및 Page 토큰 연결 필요")
        }
        return await verifyFacebook(pageID: pageID, token: token)
    }

    nonisolated static func scanThreads() async -> JarvisMetaChannelSnapshot {
        guard let token = read(threadsService) else {
            return .init(connected: false, handle: nil, checkedAt: nil, error: "Threads 사용자 토큰 연결 필요")
        }
        return await verifyThreads(token: token)
    }

    nonisolated static func recentVerifiedPosts(_ channel: JarvisSocialProfile) async -> JarvisSocialPostsResult {
        let endpoint: String
        let fields: String
        let token: String
        switch channel {
        case .facebook:
            guard let saved = read(facebookService), let pageID = UserDefaults.standard.string(forKey: pageIDPreference),
                  pageID == "1433547446509432", (await verifyFacebook(pageID: pageID, token: saved)).connected else {
                return .init(posts: nil, error: "Facebook 계정 검증 실패")
            }
            token = saved
            endpoint = "https://graph.facebook.com/v27.0/\(pageID)/posts"
            fields = "id,message,created_time,full_picture"
        case .threads:
            guard let saved = read(threadsService), (await verifyThreads(token: saved)).connected else {
                return .init(posts: nil, error: "Threads 계정 검증 실패")
            }
            token = saved
            endpoint = "https://graph.threads.net/v1.0/me/threads"
            fields = "id,text,timestamp,media_type,media_url,thumbnail_url"
        default: return .init(posts: nil, error: "지원되지 않는 채널")
        }
        return await fetchRecentPosts(endpoint: endpoint, fields: fields, token: token)
    }

    nonisolated static func fetchRecentPosts(endpoint: String, fields: String, token: String) async -> JarvisSocialPostsResult {
        struct Reply: Decodable { let data: [JarvisSocialPost] }
        guard var parts = URLComponents(string: endpoint),
              parts.scheme == "https", ["graph.facebook.com","graph.instagram.com","graph.threads.net"].contains(parts.host ?? "") else {
            return .init(posts: nil, error: "API 주소 검증 실패")
        }
        parts.queryItems = [.init(name: "fields", value: fields), .init(name: "limit", value: "8")]
        guard let url = parts.url, let (status, data) = await get(url, token: token) else {
            return .init(posts: nil, error: "게시물 API 연결 실패")
        }
        guard status == 200 else { return .init(posts: nil, error: sanitizedFailure(data, status: status)) }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .init(posts: nil, error: "게시물 응답 형식 미확인")
        }
        return .init(posts: Array(reply.data.prefix(8)), error: nil)
    }

    /// Save only a token whose live remote profile is the intended asset.
    nonisolated static func connectFacebook(pageID: String, token: String) async -> JarvisMetaChannelSnapshot {
        let checked = await verifyFacebook(pageID: pageID, token: token)
        guard checked.connected else { return checked }
        guard save(token, service: facebookService) else {
            return .init(connected: false, handle: nil, checkedAt: checked.checkedAt, error: "Mac Keychain 저장 실패")
        }
        UserDefaults.standard.set(pageID, forKey: pageIDPreference)
        return checked
    }

    nonisolated static func connectThreads(token: String) async -> JarvisMetaChannelSnapshot {
        let checked = await verifyThreads(token: token)
        guard checked.connected else { return checked }
        guard save(token, service: threadsService) else {
            return .init(connected: false, handle: nil, checkedAt: checked.checkedAt, error: "Mac Keychain 저장 실패")
        }
        return checked
    }
}
