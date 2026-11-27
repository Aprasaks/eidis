import Foundation
import AVFoundation

/// 자비스의 단일 목소리: Kokoro "Heart" (무료·오프라인, 로컬 서버 127.0.0.1:8792).
///
/// - 모든 화면의 음성(코어·대시보드·작업실·호출 인사)은 JarvisVoiceService.speak 와
///   ElevenLabsVoiceService.synthesize 를 거치며, 둘 다 여기로 먼저 보낸다.
/// - 서버: ~/.jarvis-lab/tts/jarvis_tts_server.py (venv: ~/.jarvis-lab/tts/venv). 꺼져 있으면 자비스가 띄운다.
/// - 서버를 쓸 수 없을 때만 Mac 내장 음성으로 대체한다.
/// - ElevenLabs는 지우지 않고 선택 사항으로 남긴다 (UserDefaults "jarvis.voice.engine" = "elevenlabs").
@MainActor
final class JarvisKokoroVoice {
    static let shared = JarvisKokoroVoice()

    static let voice = "af_heart"
    private static let endpoint = URL(string: "http://127.0.0.1:8792")!
    private static let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".jarvis-lab/tts")
    private var player: AVAudioPlayer?
    private var server: Process?
    private var generation = 0

    /// 기본은 Kokoro. 사용자가 명시적으로 ElevenLabs를 고른 경우만 false.
    var isPrimary: Bool { UserDefaults.standard.string(forKey: "jarvis.voice.engine") != "elevenlabs" }
    var isPlaying: Bool { player?.isPlaying == true }
    /// 코어 반응 효과용 음량 (0~1)
    var level: Float {
        guard let player, player.isPlaying else { return 0 }
        player.updateMeters()
        return max(0, min(1, (player.averagePower(forChannel: 0) + 50) / 50))
    }

    func stop() {
        generation += 1
        player?.stop()
        player = nil
    }

    /// 말하기. 성공하면 true (재생 시작), 서버를 쓸 수 없으면 false → 호출한 쪽이 Mac 음성으로 대체.
    func speak(_ text: String, speed: Double = 1.0) async -> Bool {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return true }
        stop()
        let mine = generation
        guard await ensureServer() else { return false }
        var request = URLRequest(url: Self.endpoint.appendingPathComponent("tts"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": String(phrase.prefix(1200)), "voice": Self.voice, "speed": min(max(speed, 0.6), 1.5)
        ])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 44 else { return false }
        guard mine == generation else { return true }   // 그 사이 stop()/새 문장이 들어오면 재생하지 않음
        guard let audio = try? AVAudioPlayer(data: data) else { return false }
        audio.isMeteringEnabled = true
        guard audio.prepareToPlay(), audio.play() else { return false }
        player = audio
        return true
    }

    // MARK: Server

    private func healthy() async -> Bool {
        var request = URLRequest(url: Self.endpoint.appendingPathComponent("health"))
        request.timeoutInterval = 1.5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// 서버가 없으면 띄우고 최대 25초(첫 모델 로딩) 기다린다.
    func ensureServer() async -> Bool {
        if await healthy() { return true }
        let python = Self.home.appendingPathComponent("venv/bin/python")
        let script = Self.home.appendingPathComponent("jarvis_tts_server.py")
        guard FileManager.default.isExecutableFile(atPath: python.path),
              FileManager.default.fileExists(atPath: script.path) else { return false }
        if server?.isRunning != true {
            let process = Process()
            process.executableURL = python
            process.arguments = ["-I", script.path]
            var env = ProcessInfo.processInfo.environment
            env["HF_HUB_OFFLINE"] = "1"              // 모델은 이미 받아 둠 · 실행 중 인터넷 사용 안 함
            env["HF_HUB_DISABLE_TELEMETRY"] = "1"
            process.environment = env
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            server = process
        }
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(500))
            if await healthy() { return true }
        }
        return false
    }
}
