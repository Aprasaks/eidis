import AppKit
import AVFoundation
import Foundation
import Security
import SwiftUI

/// ElevenLabs synthesis is strictly opt-in. The Voice ID is not a secret.
/// API keys are read only from the user's macOS Keychain and never from HTML,
/// source code, UserDefaults, GitHub, project memories or activity logs.
@MainActor
final class ElevenLabsVoiceService: ObservableObject {
    static let suggestedVoiceID = "O2KReOFLpoR65nz6C9Se"
    private static let service = "dev.dechive.eidis.elevenlabs"
    private static let account = "text-to-speech-api"
    private static let enabledKey = "jarvis.elevenlabs.enabled"
    private static let voiceKey = "jarvis.elevenlabs.voiceID"
    private static let modelKey = "jarvis.elevenlabs.modelID"
    private static let maxRequests = 5
    private static let maxCharacters = 600

    @Published var voiceID: String {
        didSet { defaults.set(voiceID, forKey: Self.voiceKey) }
    }
    @Published var modelID: String {
        didSet { defaults.set(modelID, forKey: Self.modelKey) }
    }
    @Published var enabled: Bool {
        didSet {
            if enabled && !keyPresent { enabled = false }
            defaults.set(enabled, forKey: Self.enabledKey)
        }
    }
    @Published private(set) var keyPresent: Bool
    @Published private(set) var status: String
    @Published private(set) var attempts = 0
    @Published private(set) var isBusy = false

    var remaining: Int { max(0, Self.maxRequests - attempts) }

    private let defaults: UserDefaults
    private let session: URLSession
    private var player: AVAudioPlayer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.voiceID = defaults.string(forKey: Self.voiceKey) ?? Self.suggestedVoiceID
        self.modelID = defaults.string(forKey: Self.modelKey) ?? "eleven_flash_v2_5"
        let hasSavedKey = Self.readKey() != nil
        self.keyPresent = hasSavedKey
        self.enabled = defaults.bool(forKey: Self.enabledKey) && hasSavedKey
        self.status = "기본 OFF · 재생 전 API 키와 사용 설정이 필요합니다."
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: configuration)
    }

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readKey() -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        guard result == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func saveKey(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 12 && key.count <= 500, let bytes = key.data(using: .utf8) else {
            status = "API 키 형식을 확인해 주세요. 입력한 키는 기록하지 않았습니다."
            return false
        }
        var insert = Self.keychainQuery()
        insert[kSecValueData as String] = bytes
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(insert as CFDictionary, nil)
        let final: OSStatus
        if result == errSecDuplicateItem {
            final = SecItemUpdate(Self.keychainQuery() as CFDictionary,
                                  [kSecValueData as String: bytes] as CFDictionary)
        } else {
            final = result
        }
        keyPresent = final == errSecSuccess
        status = keyPresent
            ? "API 키를 Mac 키체인에 저장했습니다. 음성 생성은 아직 OFF입니다."
            : "키체인에 저장할 수 없습니다. macOS 키체인 접근을 확인하세요."
        if keyPresent { enabled = false }
        return keyPresent
    }

    func removeKey() {
        let code = SecItemDelete(Self.keychainQuery() as CFDictionary)
        if code == errSecSuccess || code == errSecItemNotFound {
            enabled = false
            keyPresent = false
            player?.stop()
            player = nil
            status = "Mac 키체인에서 ElevenLabs API 키를 지웠습니다."
        } else {
            status = "키체인에서 삭제하지 못했습니다. 키체인 접근을 확인하세요."
        }
    }

    func preview(fallback: JarvisVoiceService) async {
        await synthesize("네, 듣고 있습니다. 요청하신 내용을 확인하겠습니다.",
                         fallback: fallback, explicitlyPreviewed: true)
    }

    func speak(_ text: String, fallback: JarvisVoiceService) async {
        await synthesize(text, fallback: fallback, explicitlyPreviewed: false)
    }

    private func synthesize(_ text: String, fallback: JarvisVoiceService,
                            explicitlyPreviewed: Bool) async {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        guard (enabled || explicitlyPreviewed) && keyPresent else {
            fallback.speak(phrase)
            if explicitlyPreviewed {
                status = "ElevenLabs 미리 듣기에는 저장된 API 키가 필요합니다. Mac 음성으로 대체했습니다."
            }
            return
        }
        guard !isBusy else {
            status = "음성 생성 중입니다. 중복 호출을 막았습니다."
            return
        }
        guard remaining > 0 else {
            enabled = false
            status = "이번 앱 실행에서 ElevenLabs 요청 5회를 사용했습니다. Mac 기본 음성으로 전환합니다."
            fallback.speak(phrase)
            return
        }
        guard phrase.count <= Self.maxCharacters else {
            status = "600자를 넘는 응답은 비용·정보 노출을 줄이기 위해 Mac에서만 읽습니다."
            fallback.speak(phrase)
            return
        }
        let id = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.range(of: "^[A-Za-z0-9]{20}$", options: .regularExpression) != nil else {
            status = "Voice ID는 20자리 영문·숫자여야 합니다. Mac 음성으로 대체합니다."
            fallback.speak(phrase)
            return
        }
        guard ["eleven_flash_v2_5", "eleven_multilingual_v2"].contains(modelID),
              let key = Self.readKey() else {
            status = "ElevenLabs 모델 또는 API 키를 확인해 주세요."
            fallback.speak(phrase)
            return
        }
        guard let url = URL(string:
            "https://api.elevenlabs.io/v1/text-to-speech/\(id)?output_format=mp3_44100_128"
        ) else { fallback.speak(phrase); return }

        // Every request, including a preview, can use credits. Do not retry.
        attempts += 1
        isBusy = true
        defer { isBusy = false }
        status = "ElevenLabs 음성 생성 중 · 이번 실행 \(attempts)/5회 요청"
        player?.stop()
        player = nil
        fallback.stop()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": phrase, "model_id": modelID
        ])
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw ElevenLabsVoiceError.invalidResponse
            }
            switch response.statusCode {
            case 200: break
            case 401, 403: throw ElevenLabsVoiceError.invalidKey
            case 402, 429: throw ElevenLabsVoiceError.limitOrCredits
            default: throw ElevenLabsVoiceError.serviceUnavailable
            }
            guard data.count > 100, data.count <= 3_000_000,
                  response.value(forHTTPHeaderField: "Content-Type")?
                    .lowercased().contains("audio") == true else {
                throw ElevenLabsVoiceError.invalidResponse
            }
            let audio = try AVAudioPlayer(data: data)
            guard audio.prepareToPlay(), audio.play() else {
                throw ElevenLabsVoiceError.playbackUnavailable
            }
            player = audio
            status = "ElevenLabs 음성 재생 중 · 요청 \(attempts)/5회 (크레딧 소모 가능)"
        } catch {
            // Error content, API key and raw provider response are never logged.
            status = "ElevenLabs 음성 생성 실패: \((error as? ElevenLabsVoiceError)?.description ?? "네트워크 또는 재생 오류"). Mac 기본 음성으로 전환했습니다."
            fallback.speak(phrase)
        }
    }
}

private enum ElevenLabsVoiceError: Error {
    case invalidResponse, invalidKey, limitOrCredits, serviceUnavailable, playbackUnavailable

    var description: String {
        switch self {
        case .invalidResponse: return "오디오 응답이 올바르지 않습니다"
        case .invalidKey: return "API 키 또는 음성 사용 권한을 확인해 주세요"
        case .limitOrCredits: return "크레딧·요청 한도를 확인해 주세요"
        case .serviceUnavailable: return "서비스에서 요청을 처리하지 못했습니다"
        case .playbackUnavailable: return "Mac에서 오디오를 재생하지 못했습니다"
        }
    }
}
