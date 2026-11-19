import AppKit
import AVFoundation
import Foundation
import Security
import SwiftUI

/// ElevenLabs synthesis is strictly opt-in. The Voice ID is not a secret.
/// API keys are read only from the user's macOS Keychain and never from HTML,
/// source code, UserDefaults, GitHub, project memories or activity logs.
struct ElevenLabsLibraryVoice: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
    let gender: String
    let accent: String
    let korean: Bool
    let sampleURL: URL?
}

@MainActor
final class ElevenLabsVoiceService: ObservableObject {
    static let shared = ElevenLabsVoiceService()
    static let suggestedVoiceID = "O2KReOFLpoR65nz6C9Se"
    nonisolated private static let service = "dev.dechive.eidis.elevenlabs"
    nonisolated private static let account = "text-to-speech-api"
    private static let enabledKey = "jarvis.elevenlabs.enabled"
    private static let voiceKey = "jarvis.elevenlabs.voiceID"
    private static let modelKey = "jarvis.elevenlabs.modelID"
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
    @Published private(set) var isCheckingConnection = false
    @Published private(set) var libraryVoices: [ElevenLabsLibraryVoice] = []
    @Published private(set) var libraryStatus = "ElevenLabs 계정에 저장된 목소리를 가져올 수 있습니다."
    @Published private(set) var isLoadingLibrary = false
    private var samplePlayer: AVPlayer?
    private static let summonGreeting = "네, 자비스입니다."
    // Cache only the fixed greeting for the lifetime of this app process.
    // Dynamic answers still use the existing per-request synthesis path.
    private var greetingCache: (voiceID: String, modelID: String, audio: Data)?
    private var speechGeneration = 0


    private let defaults: UserDefaults
    private let session: URLSession
    private var player: AVAudioPlayer?
    private var keyStateRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.voiceID = defaults.string(forKey: Self.voiceKey) ?? Self.suggestedVoiceID
        self.modelID = defaults.string(forKey: Self.modelKey) ?? "eleven_flash_v2_5"
        // Do NOT synchronously access the macOS Keychain on the SwiftUI
        // main thread during app launch. It can wait for a locked keychain,
        // preventing the entire JARVIS window and bundled server from opening.
        let hasSavedKey = false
        self.keyPresent = hasSavedKey
        self.enabled = defaults.bool(forKey: Self.enabledKey) && hasSavedKey
        self.status = "ElevenLabs 키체인 상태 확인 중 · 음성 생성은 기본 OFF"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: configuration)
        // Preview builds have a separate bundle identity and must never request
        // access to the production user's ElevenLabs Keychain item.
        if Bundle.main.bundleIdentifier == "dev.dechive.eidis" {
            Task { [weak self] in
                await self?.refreshSavedKeyAvailability()
            }
        } else {
            self.status = "독립 시험 앱: ElevenLabs 키체인 자동 조회 생략"
        }
    }

    private func refreshSavedKeyAvailability() async {
        let revision = keyStateRevision
        // Keychain lookup may block until the Mac session is unlocked.
        // Keep that wait entirely off SwiftUI's main actor.
        let hasSavedKey = await Task.detached(priority: .utility) {
            Self.readKey() != nil
        }.value
        guard revision == keyStateRevision else { return }
        keyPresent = hasSavedKey
        enabled = defaults.bool(forKey: Self.enabledKey) && hasSavedKey
        status = hasSavedKey
            ? (enabled ? "ElevenLabs 키 확인됨 · 사용 설정 ON"
                       : "ElevenLabs 키 확인됨 · 음성 생성 OFF")
            : "ElevenLabs API 키가 없거나 키체인이 잠겨 있습니다. 기본 Mac 음성을 사용합니다."
    }

    nonisolated private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    nonisolated private static func readKey() -> String? {
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
        keyStateRevision += 1
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
            keyStateRevision += 1
            enabled = false
            keyPresent = false
            player?.stop()
            player = nil
            status = "Mac 키체인에서 ElevenLabs API 키를 지웠습니다."
        } else {
            status = "키체인에서 삭제하지 못했습니다. 키체인 접근을 확인하세요."
        }
    }

    /// Explicit read-only metadata check. No speech generation, no audio, no TTS credits.
    func checkVoiceConnection() async {
        guard !isBusy && !isCheckingConnection else { return }
        let id = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.range(of: "^[A-Za-z0-9]{20}$", options: .regularExpression) != nil else {
            status = "Voice ID 형식 오류: 영문·숫자 20자리인지 확인해 주세요."
            return
        }
        isCheckingConnection = true
        defer { isCheckingConnection = false }
        let key = await Task.detached(priority: .userInitiated) {
            Self.readKey()
        }.value
        guard let key else {
            keyPresent = false
            enabled = false
            status = "키체인에서 API 키를 읽을 수 없습니다. 앱에서 키를 다시 저장해 주세요."
            return
        }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/voices/\(id)") else {
            status = "Voice ID 주소가 올바르지 않습니다."
            return
        }
        status = "ElevenLabs 음성 접근 확인 중… (음성 생성 없음)"
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (payload, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                status = "ElevenLabs 응답 형식을 확인하지 못했습니다."
                return
            }
            switch http.statusCode {
            case 200:
                let details = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
                let confirmedID = details?["voice_id"] as? String
                guard confirmedID == id else {
                    status = "응답의 Voice ID가 일치하지 않습니다. 설정을 확인해 주세요."
                    return
                }
                let rawName = details?["name"] as? String ?? "이름 미표시"
                let name = String(rawName.prefix(60))
                status = "연결 확인 성공 · 음성 \(name) · Voice ID 접근 가능. 실제 음성 재생은 유료 미리 듣기로 별도 확인해야 합니다."
            case 401:
                status = "인증 실패(401) · ElevenLabs API 키를 확인하고 다시 저장해 주세요."
            case 403:
                status = "접근 거부(403) · API 키 권한 또는 계정에서 이 음성을 사용할 수 있는지 확인해 주세요."
            case 404:
                status = "음성을 찾지 못함(404) · Voice ID와 계정의 음성 라이브러리를 확인해 주세요."
            case 429:
                status = "ElevenLabs 조회 요청 한도(429)에 도달했습니다."
            default:
                status = "ElevenLabs 연결 확인 실패 · HTTP \(http.statusCode). 계정과 서비스 상태를 확인해 주세요."
            }
        } catch {
            status = "ElevenLabs 네트워크 연결 확인 실패 · 인터넷 연결이나 서비스 상태를 확인해 주세요."
        }
    }

    /// Show only structured error categories, never body text, API key, or account details.
    private static func safeAPIErrorCode(from payload: Data, httpStatus: Int) -> String {
        guard let body = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            return "HTTP \(httpStatus) · 응답 형식 확인 불가"
        }
        let detail = body["detail"] as? [String: Any] ?? body
        let fields = ["type", "code", "status", "param"]
        let safeValues = fields.compactMap { name -> String? in
            guard let value = detail[name] as? String,
                  value.range(of: "^[A-Za-z0-9_.-]{1,60}$", options: .regularExpression) != nil
            else { return nil }
            return "\(name):\(value)"
        }
        return "HTTP \(httpStatus)" + (safeValues.isEmpty ? " · 세부 오류 코드 없음" : " · " + safeValues.joined(separator: " · "))
    }

    /// List voice metadata only (GET). No speech generation or credits.
    func fetchVoiceLibrary() async {
        guard !isLoadingLibrary && !isBusy else { return }
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        libraryStatus = "ElevenLabs 키체인 접근 및 음성 목록 확인 중…"
        let key = await Task.detached(priority: .userInitiated) {
            Self.readKey()
        }.value
        guard let key else {
            libraryStatus = "Mac 키체인에 저장된 ElevenLabs API 키를 읽지 못했습니다. 키체인 접근을 허용하거나 음성 탭에서 키를 등록해 주세요."
            return
        }
        keyPresent = true
        var all: [ElevenLabsLibraryVoice] = []
        var cursor: String?
        var seen = Set<String>()
        do {
            for _ in 0..<3 {
                var parts = URLComponents(string: "https://api.elevenlabs.io/v2/voices")!
                var query = [URLQueryItem(name: "page_size", value: "100")]
                if let cursor { query.append(URLQueryItem(name: "next_page_token", value: cursor)) }
                parts.queryItems = query
                guard let url = parts.url else { break }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue(key, forHTTPHeaderField: "xi-api-key")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 18
                var (payload, response) = try await session.data(for: request)
                guard var http = response as? HTTPURLResponse else { throw ElevenLabsVoiceError.invalidResponse }
                let firstAttempt = http.statusCode == 200 ? "" : "v2 " + Self.safeAPIErrorCode(from: payload, httpStatus: http.statusCode)
                // Some account/API combinations reject v2 filters (HTTP 400).
                // Legacy v1 voices is a documented read-only fallback, no TTS charges.
                if [400, 404, 422].contains(http.statusCode) && cursor == nil {
                    let fallbackURL = URL(string: "https://api.elevenlabs.io/v1/voices")!
                    var fallback = URLRequest(url: fallbackURL)
                    fallback.httpMethod = "GET"
                    fallback.timeoutInterval = 18
                    fallback.setValue(key, forHTTPHeaderField: "xi-api-key")
                    fallback.setValue("application/json", forHTTPHeaderField: "Accept")
                    (payload, response) = try await session.data(for: fallback)
                    guard let fallbackHTTP = response as? HTTPURLResponse else { throw ElevenLabsVoiceError.invalidResponse }
                    http = fallbackHTTP
                }
                guard http.statusCode == 200 else {
                    let lastAttempt = Self.safeAPIErrorCode(from: payload, httpStatus: http.statusCode)
                    libraryStatus = "목소리 목록 실패 · " + (firstAttempt.isEmpty ? "" : firstAttempt + " / ") +
                        "최종 " + lastAttempt + " · API 설정과 권한을 확인해 주세요."
                    return
                }
                let root = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
                guard let rows = root?["voices"] as? [[String: Any]] else { throw ElevenLabsVoiceError.invalidResponse }
                for item in rows {
                    guard let id = item["voice_id"] as? String,
                          id.range(of: "^[A-Za-z0-9]{20}$", options: .regularExpression) != nil,
                          !seen.contains(id) else { continue }
                    seen.insert(id)
                    let labels = item["labels"] as? [String: String] ?? [:]
                    let category = item["category"] as? String ?? ""
                    let gender = labels["gender"] ?? "미표시"
                    let accent = labels["accent"] ?? ""
                    let versions = item["verified_languages"] as? [[String: Any]] ?? []
                    let korean = versions.contains { ($0["language"] as? String)?.lowercased() == "ko" }
                        || (labels["language"]?.lowercased().contains("korean") ?? false)
                    let preview = item["preview_url"] as? String
                    let sampleURL = preview.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
                    all.append(ElevenLabsLibraryVoice(id: id,
                        name: String((item["name"] as? String ?? "이름 없음").prefix(90)),
                        category: category, gender: gender, accent: accent,
                        korean: korean, sampleURL: sampleURL))
                }
                if root?["has_more"] as? Bool == true,
                   let next = root?["next_page_token"] as? String,
                   !next.isEmpty, next != cursor { cursor = next }
                else { cursor = nil; break }
            }
            libraryVoices = all.sorted { a, b in
                let ar = (a.korean ? 0 : 2) + (a.gender.lowercased() == "female" ? 0 : 1)
                let br = (b.korean ? 0 : 2) + (b.gender.lowercased() == "female" ? 0 : 1)
                return ar == br ? a.name.localizedStandardCompare(b.name) == .orderedAscending : ar < br
            }
            libraryStatus = all.isEmpty ? "사용 가능한 음성이 조회되지 않았습니다. ElevenLabs의 My Voices에서 음성을 추가해 주세요." :
                "조회 완료 · \(all.count)개 (목록 조회는 음성 크레딧 미사용)" + (cursor != nil ? " · 처음 300개만 표시" : "")
        } catch {
            libraryStatus = "목소리 목록 연결 실패. ElevenLabs 계정·키체인 권한·네트워크를 확인해 주세요."
        }
    }

    /// Select only. This does not enable paid synthesis automatically.
    func selectLibraryVoice(_ voice: ElevenLabsLibraryVoice) {
        guard libraryVoices.contains(voice) else { return }
        voiceID = voice.id
        libraryStatus = "선택됨: \(voice.name). 유료 합성 설정은 변경하지 않았습니다. 현재 \(enabled ? "ON" : "OFF")입니다."
    }

    /// Play a provider-supplied preview_url, not text-to-speech generation.
    func playLibrarySample(_ voice: ElevenLabsLibraryVoice) {
        guard libraryVoices.contains(voice), let url = voice.sampleURL,
              url.scheme == "https" else {
            libraryStatus = "이 목소리에는 재생 가능한 미리 듣기 주소가 없습니다."
            return
        }
        samplePlayer?.pause()
        samplePlayer = AVPlayer(url: url)
        samplePlayer?.play()
        libraryStatus = "ElevenLabs 제공 샘플 재생 중 · 음성 생성 요청 없음. 샘플 언어는 한국어가 아닐 수 있습니다."
    }

    /// The fullscreen summon is explicitly initiated by the user. A saved opt-in
    /// is required; do not claim listening or start the microphone.
    func speakSummonGreeting(fallback: JarvisVoiceService) async {
        if !keyPresent { await refreshSavedKeyAvailability() }
        guard !Task.isCancelled else { return }
        if enabled, let cached = greetingCache,
           cached.voiceID == voiceID, cached.modelID == modelID {
            do {
                let audio = try AVAudioPlayer(data: cached.audio)
                fallback.stop()
                player?.stop()
                guard audio.prepareToPlay(), !Task.isCancelled, audio.play() else { return }
                player = audio
                status = "소환 인사 재생 중 · 저장된 오디오 재사용 (추가 크레딧 없음)"
                NSLog("JARVIS: fullscreen greeting played from in-memory cache")
                return
            } catch {
                greetingCache = nil
            }
        }
        await synthesize(Self.summonGreeting, fallback: fallback,
                         explicitlyPreviewed: false, isSummonGreeting: true)
    }

    /// Esc cancels in-flight greeting playback/response and prevents late audio.
    /// Normal voice panel can be opened separately after dismissal.
    func stopSpeakingNow() {
        speechGeneration += 1
        NSLog("JARVIS: voice playback canceled on overlay dismissal")
        player?.stop()
        player = nil
        samplePlayer?.pause()
        status = "자비스 소환 음성 중단 · Esc"
    }

    /// Wait for either ElevenLabs or the offline Mac fallback to finish speaking.
    /// Each 150ms pause is cancellable; Esc stops playback and the next question.
    func waitForOutputToFinish(fallback: JarvisVoiceService) async {
        for _ in 0..<400 {
            if Task.isCancelled { return }
            if !isBusy && player?.isPlaying != true && !fallback.isSpeaking { return }
            try? await Task.sleep(for: .milliseconds(150))
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
                            explicitlyPreviewed: Bool,
                            isSummonGreeting: Bool = false) async {
        let generation = speechGeneration
        guard !Task.isCancelled else { return }
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
        guard ["eleven_flash_v2_5", "eleven_multilingual_v2"].contains(modelID) else {
            status = "ElevenLabs 모델 또는 API 키를 확인해 주세요."
            fallback.speak(phrase)
            return
        }
        let key = await Task.detached(priority: .userInitiated) {
            Self.readKey()
        }.value
        guard !Task.isCancelled, generation == speechGeneration else { return }
        guard let key else {
            status = "ElevenLabs API 키를 읽지 못했습니다. Mac 기본 음성으로 전환합니다."
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
        status = "ElevenLabs 음성 생성 중 · 이번 실행 \(attempts)회 요청 · 크레딧 사용 가능"
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
            // Dismissal wins even when a paid request finishes after Esc.
            guard !Task.isCancelled, generation == speechGeneration else { return }
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
            guard audio.prepareToPlay(), !Task.isCancelled,
                  generation == speechGeneration, audio.play() else {
                throw ElevenLabsVoiceError.playbackUnavailable
            }
            player = audio
            if isSummonGreeting {
                greetingCache = (voiceID: id, modelID: modelID, audio: data)
                NSLog("JARVIS: fullscreen greeting ElevenLabs playback started; cached in memory")
            }
            status = "ElevenLabs 음성 재생 중 · 이번 실행 \(attempts)회 요청 (크레딧 소모 가능)"
        } catch {
            guard !Task.isCancelled, generation == speechGeneration else { return }
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
