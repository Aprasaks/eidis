import Foundation
import Security

/// The owner enters the Meta access token locally. It is never sent to the
/// JARVIS HTTP server, persisted in UserDefaults, or included in logs/URLs.
/// This connector only performs GET requests for the fixed DECHIVE.WIKI account.
struct JarvisInstagramSnapshot: Sendable {
    let username: String?
    let followersCount: Int?
    let mediaCount: Int?
    let checkedAt: Date
    let error: String?
    let connected: Bool
}

enum JarvisInstagramLoginMode: String, CaseIterable, Identifiable, Sendable {
    case facebookBusiness
    case instagramLogin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .facebookBusiness: "Facebook Business 토큰"
        case .instagramLogin: "Instagram 로그인 토큰"
        }
    }
}

enum JarvisMetaInstagramService {
    nonisolated private static let modePreference = "jarvis.meta.instagram.authMode"
    nonisolated static func savedMode() -> JarvisInstagramLoginMode {
        JarvisInstagramLoginMode(rawValue: UserDefaults.standard.string(forKey: modePreference) ?? "") ?? .facebookBusiness
    }
    nonisolated static func saveMode(_ mode: JarvisInstagramLoginMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: modePreference)
    }

    nonisolated static let accountID = "17841447171659454"
    nonisolated static let accountName = "dechive.wiki"
    nonisolated private static let service = "dev.dechive.eidis.meta.instagram.wiki"
    nonisolated private static let keychainAccount = "graph-api-access-token"

    private struct Profile: Decodable {
        let id: String
        let username: String?
        let followers_count: Int?
        let media_count: Int?
    }

    /// Keychain lookup is intentionally run off the UI actor.
    nonisolated static func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var output: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &output) == errSecSuccess,
              let data = output as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// No write to Keychain happens until the token passes a real API read
    /// for the exact account name and account ID.
    nonisolated static func saveVerifiedToken(_ token: String) -> Bool {
        guard token.utf8.count >= 32 && token.utf8.count < 8192 else { return false }
        let payload = Data(token.utf8)
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount
        ]
        let update = [kSecValueData as String: payload]
        let result = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var insert = lookup
        insert[kSecValueData as String] = payload
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    nonisolated static func scanSaved() async -> JarvisInstagramSnapshot {
        guard let token = readToken() else {
            return JarvisInstagramSnapshot(username: nil, followersCount: nil,
                  mediaCount: nil, checkedAt: Date(), error: nil, connected: false)
        }
        return await verify(token: token, mode: savedMode())
    }

    nonisolated static func verify(token: String, mode: JarvisInstagramLoginMode = .facebookBusiness) async -> JarvisInstagramSnapshot {
        guard token.utf8.count >= 32 && token.utf8.count < 8192,
              !token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            return failure("토큰 형식이 올바르지 않습니다.")
        }
        // Facebook Business and direct Instagram Login tokens are different
        // grants. The owner selects the login flow; never guess a token type.
        let url: URL
        switch mode {
        case .facebookBusiness:
            url = URL(string: "https://graph.facebook.com/v27.0/\(accountID)?fields=id,username,followers_count,media_count")!
        case .instagramLogin:
            url = URL(string: "https://graph.instagram.com/v27.0/me?fields=id,username")!
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        do {
            let (data, response) = try await URLSession(configuration: config).data(for: request)
            guard data.count <= 100_000,
                  let http = response as? HTTPURLResponse else {
                return failure("Meta 응답 형식을 확인할 수 없습니다.")
            }
            guard http.statusCode == 200 else {
                // Only numeric error metadata; never surface raw provider
                // messages that might include user identifiers or tokens.
                return failure(JarvisMetaChannels.sanitizedFailure(data, status: http.statusCode))
            }
            guard let profile = try? JSONDecoder().decode(Profile.self, from: data),
                  (mode == .instagramLogin || profile.id == accountID),
                  !profile.id.isEmpty,
                  profile.username?.lowercased() == accountName else {
                return failure("토큰이 DECHIVE.WIKI Instagram 계정과 일치하지 않습니다.")
            }
            return JarvisInstagramSnapshot(
                username: profile.username, followersCount: profile.followers_count,
                mediaCount: profile.media_count, checkedAt: Date(),
                error: nil, connected: true)
        } catch {
            return failure("Meta API 네트워크 연결 또는 응답 처리에 실패했습니다.")
        }
    }

    private nonisolated static func failure(_ message: String) -> JarvisInstagramSnapshot {
        JarvisInstagramSnapshot(username: nil, followersCount: nil,
              mediaCount: nil, checkedAt: Date(), error: message, connected: false)
    }
}
