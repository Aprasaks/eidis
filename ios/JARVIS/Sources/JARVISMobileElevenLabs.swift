import AVFoundation
import Foundation
import Security

/// Private, opt-in ElevenLabs prototype for the owner's personal iPhone.
/// The Voice ID is the same non-secret identifier configured on the Mac.
/// The API key is NEVER shipped in the bundle, logs, preferences or source.
/// A production/distributed app must use an authenticated backend or
/// short-lived tokens instead of a persistent client-side API key.
@MainActor
final class JARVISMobileElevenLabs: ObservableObject {
    static let macVoiceID = "6Vgh4FaCc0SCcWPwcyXa"
    nonisolated private static let service = "dev.dechive.jarvis.mobile.elevenlabs"
    nonisolated private static let account = "private-tts-key"
    private static let enabledPreference = "jarvis.mobile.elevenlabs.enabled"
    private static let voicePreference = "jarvis.mobile.elevenlabs.voiceID"
    private static let modelPreference = "jarvis.mobile.elevenlabs.modelID"
    private static let limit = 600

    @Published var voiceID: String {
        didSet {
            defaults.set(voiceID, forKey: Self.voicePreference)
        }
    }
    @Published var modelID: String {
        didSet {
            defaults.set(modelID, forKey: Self.modelPreference)
        }
    }
    @Published private(set) var isConfigured = false
    @Published private(set) var enabled = false
    @Published private(set) var status = "기본 iPhone 음성 사용 중"
    @Published private(set) var generatedRequests = 0
    @Published private(set) var isChecking = false
    @Published private(set) var isGenerating = false

    private let defaults: UserDefaults
    private let session: URLSession

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voiceID = defaults.string(forKey: Self.voicePreference) ?? Self.macVoiceID
        modelID = defaults.string(forKey: Self.modelPreference) ?? "eleven_flash_v2_5"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        session = URLSession(configuration: configuration)
        // This is metadata only; don't print or read the key into UI state.
        isConfigured = Self.readKey() != nil
        enabled = isConfigured && defaults.bool(forKey: Self.enabledPreference)
        if enabled { status = "ElevenLabs 사용 설정 · 음성 생성에 크레딧 사용 가능" }
    }

    nonisolated private static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    nonisolated private static func readKey() -> String? {
        var request = query()
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let bytes = item as? Data,
              let value = String(data: bytes, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    private var validVoiceID: String? {
        let value = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(of: "^[A-Za-z0-9]{20}$", options: .regularExpression) == nil
            ? nil : value
    }

    func saveKey(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (12...500).contains(key.count),
              let bytes = key.data(using: .utf8) else {
            status = "API 키 형식을 확인해 주세요. 입력한 키는 기록하지 않았습니다."
            return false
        }
        var insertion = Self.query()
        insertion[kSecValueData as String] = bytes
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let first = SecItemAdd(insertion as CFDictionary, nil)
        let result: OSStatus
        if first == errSecDuplicateItem {
            result = SecItemUpdate(Self.query() as CFDictionary,
                                   [kSecValueData as String: bytes] as CFDictionary)
        } else {
            result = first
        }
        isConfigured = result == errSecSuccess
        setEnabled(false) // never silently opt into credit use
        status = isConfigured
            ? "키를 iPhone 키체인에 저장했어요. ElevenLabs 사용은 아직 꺼져 있어요."
            : "키체인 저장 실패 · 이 iPhone이 잠금 해제되어 있는지 확인해 주세요."
        return isConfigured
    }

    func deleteKey() {
        let result = SecItemDelete(Self.query() as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            status = "키체인 키 삭제 실패"
            return
        }
        isConfigured = false
        setEnabled(false)
        status = "iPhone 키체인에서 ElevenLabs 키를 삭제했어요."
    }

    func setEnabled(_ newValue: Bool) {
        enabled = newValue && isConfigured && validVoiceID != nil
            && ["eleven_flash_v2_5", "eleven_multilingual_v2"].contains(modelID)
        defaults.set(enabled, forKey: Self.enabledPreference)
        status = enabled
            ? "ElevenLabs 켜짐 · 새 음성 생성마다 크레딧 사용 가능"
            : (newValue ? "키·Voice ID·모델을 먼저 확인해 주세요." : "ElevenLabs 꺼짐 · 기본 iPhone 음성 사용")
    }

    /// Provider read-only metadata request. No voice generation/credits.
    func checkConnection() async {
        guard !isChecking && !isGenerating else { return }
        guard let id = validVoiceID else {
            status = "Voice ID는 영문·숫자 20자리여야 해요."
            return
        }
        isChecking = true
        defer { isChecking = false }
        guard let key = await Task.detached(priority: .userInitiated, operation: {
            Self.readKey()
        }).value else {
            isConfigured = false
            setEnabled(false)
            status = "이 iPhone의 키체인에 ElevenLabs 키가 없어요."
            return
        }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices/\(id)")!)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                status = "연결 응답을 확인하지 못했어요."
                return
            }
            if http.statusCode == 200,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["voice_id"] as? String == id {
                status = "맥과 동일한 Voice ID 접근 확인됨 · 테스트 음성 생성은 하지 않았어요."
            } else {
                status = "ElevenLabs 음성 접근 실패 · HTTP \(http.statusCode). 키와 권한을 확인해 주세요."
            }
        } catch {
            status = "ElevenLabs 연결 실패 · 인터넷 연결을 확인해 주세요."
        }
    }

    /// One call per utterance. This can spend credits; no retries or
    /// automatic calls when disabled, over limit, or missing credentials.
    func generateAudio(_ phrase: String) async -> Data? {
        guard enabled, !isGenerating,
              let id = validVoiceID,
              ["eleven_flash_v2_5", "eleven_multilingual_v2"].contains(modelID) else {
            return nil
        }
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= Self.limit else {
            status = "600자를 초과한 음성은 기본 iPhone 목소리로 읽어요."
            return nil
        }
        guard let key = await Task.detached(priority: .userInitiated, operation: {
            Self.readKey()
        }).value else {
            status = "iPhone 키체인에서 키를 찾지 못했어요."
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(id)?output_format=mp3_44100_128")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": modelID,
            "voice_settings": ["speed": 0.90]
        ])

        isGenerating = true
        generatedRequests += 1
        status = "ElevenLabs 음성 생성 요청 \(generatedRequests)회 · 크레딧 사용 가능"
        defer { isGenerating = false }
        do {
            let (bytes, response) = try await session.data(for: request)
            guard !Task.isCancelled else { return nil }
            guard let http = response as? HTTPURLResponse else {
                status = "ElevenLabs 응답 오류"
                return nil
            }
            guard http.statusCode == 200 else {
                status = [402, 429].contains(http.statusCode)
                    ? "ElevenLabs 크레딧·사용 한도를 확인해 주세요. 기본 음성으로 대체해요."
                    : "ElevenLabs 생성 실패 (HTTP \(http.statusCode)). 기본 음성으로 대체해요."
                return nil
            }
            guard (100...3_000_000).contains(bytes.count),
                  http.value(forHTTPHeaderField: "Content-Type")?
                    .lowercased().contains("audio") == true else {
                status = "ElevenLabs 오디오 형식 오류 · 기본 음성으로 대체해요."
                return nil
            }
            status = "ElevenLabs 음성 수신 완료 · 크레딧 사용 가능"
            return bytes
        } catch {
            guard !Task.isCancelled else { return nil }
            status = "ElevenLabs 네트워크 오류 · 기본 음성으로 대체해요."
            return nil
        }
    }
}
