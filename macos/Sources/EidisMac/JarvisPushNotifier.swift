import Foundation
import CryptoKit

/// 아이폰 자비스 잠금화면 알림 (APNs, SNS 영역 전용 파일).
///
/// - 키: ~/.jarvis-lab/secrets/AuthKey_<KeyID>.p8 (0600). 자비스가 서명할 때만 읽고, 내용은 어디에도 남기지 않는다.
/// - 기기 토큰: 아이폰이 인증된 연결(근거리/Tailscale)로 보낸 것만 ~/.jarvis-lab/push/devices.json 에 저장.
/// - 보내는 내용: 제목·본문·열 화면 이름뿐. 토큰·파일 경로·개인정보는 담지 않는다.
@MainActor
final class JarvisPushNotifier: ObservableObject {
    static let shared = JarvisPushNotifier()

    @Published private(set) var lastResult: String?
    private static let teamID = "Z63TP6ZRVH"
    private static let topic = "dev.dechive.jarvis.mobile"
    private static let secrets = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".jarvis-lab/secrets")
    private static let devicesFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".jarvis-lab/push/devices.json")
    private var cachedJWT: (token: String, made: Date)?

    // MARK: Device tokens

    struct Device: Codable { let token: String; let environment: String; let registeredAt: Date }

    private func devices() -> [Device] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: Self.devicesFile)).flatMap { try? decoder.decode([Device].self, from: $0) } ?? []
    }

    /// 인증된 아이폰 요청(kind "registerPushToken")으로만 호출된다.
    func register(token: String, environment: String) -> Bool {
        guard token.range(of: "^[0-9a-f]{64,200}$", options: .regularExpression) != nil,
              ["sandbox", "production"].contains(environment) else { return false }
        var list = devices().filter { $0.token != token }
        list.append(Device(token: token, environment: environment, registeredAt: Date()))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = .prettyPrinted
        try? FileManager.default.createDirectory(at: Self.devicesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(Array(list.suffix(3))) else { return false }
        try? data.write(to: Self.devicesFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.devicesFile.path)
        return true
    }

    var hasDevice: Bool { !devices().isEmpty }

    // MARK: Sending

    /// page: 아이폰에서 열 화면 (예: "social")
    func send(title: String, body: String, page: String = "social") {
        Task { await sendNow(title: title, body: body, page: page) }
    }

    @discardableResult
    func sendNow(title: String, body: String, page: String = "social") async -> String {
        let targets = devices()
        guard !targets.isEmpty else { lastResult = "등록된 아이폰 없음"; return lastResult! }
        guard let jwt = jwtToken() else { lastResult = "APNs 키 없음 또는 읽기 실패"; return lastResult! }
        let payload: [String: Any] = ["aps": ["alert": ["title": title, "body": body], "sound": "default"], "page": page]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "알림 내용 오류" }
        var results: [String] = []
        for device in targets {
            let host = device.environment == "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com"
            guard let url = URL(string: "https://\(host)/3/device/\(device.token)") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = data
            req.timeoutInterval = 15
            req.setValue("bearer " + jwt, forHTTPHeaderField: "authorization")
            req.setValue(Self.topic, forHTTPHeaderField: "apns-topic")
            req.setValue("alert", forHTTPHeaderField: "apns-push-type")
            req.setValue("10", forHTTPHeaderField: "apns-priority")
            let status = (try? await URLSession.shared.data(for: req)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode } ?? 0
            results.append(status == 200 ? "전송됨" : "실패(\(status))")
        }
        lastResult = results.joined(separator: ", ")
        return lastResult!
    }

    /// ES256 JWT (Apple 권장: 20~60분마다 갱신)
    private func jwtToken() -> String? {
        if let cached = cachedJWT, Date().timeIntervalSince(cached.made) < 40 * 60 { return cached.token }
        guard let file = ((try? FileManager.default.contentsOfDirectory(at: Self.secrets, includingPropertiesForKeys: nil)) ?? [])
                .first(where: { $0.lastPathComponent.hasPrefix("AuthKey_") && $0.pathExtension == "p8" }),
              let pem = try? String(contentsOf: file, encoding: .utf8),
              let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else { return nil }
        let keyID = String(file.deletingPathExtension().lastPathComponent.dropFirst("AuthKey_".count))
        func b64(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let header = b64(Data(#"{"alg":"ES256","kid":"\#(keyID)"}"#.utf8))
        let claims = b64(Data(#"{"iss":"\#(Self.teamID)","iat":\#(Int(Date().timeIntervalSince1970))}"#.utf8))
        let input = header + "." + claims
        guard let signature = try? key.signature(for: Data(input.utf8)) else { return nil }
        let token = input + "." + b64(signature.rawRepresentation)
        cachedJWT = (token, Date())
        return token
    }
}
