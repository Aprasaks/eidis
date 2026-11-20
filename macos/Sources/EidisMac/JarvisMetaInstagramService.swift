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

enum JarvisMetaInstagramService {
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
        return await verify(token: token)
    }

    nonisolated static func verify(token: String) async -> JarvisInstagramSnapshot {
        guard token.utf8.count >= 32 && token.utf8.count < 8192,
              !token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            return failure("토큰 형식이 올바르지 않습니다.")
        }
        // This is a System User Access Token produced by Business Login for
        // the Unified Instagram API, not an Instagram-only login token.
        let url = URL(string: "https://graph.facebook.com/v27.0/\(accountID)?fields=id,username,followers_count,media_count")!
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
                // Deliberately never return Graph API error body or request URL.
                return failure("Meta Graph API 요청 실패 (HTTP \(http.statusCode)). 권한·토큰·자산을 확인해 주세요.")
            }
            guard let profile = try? JSONDecoder().decode(Profile.self, from: data),
                  profile.id == accountID, profile.username?.lowercased() == accountName else {
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
