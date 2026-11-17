import AppKit
import Foundation

/// Private, loopback-only Python companion for the native Mac app.
/// Starts only when the installed app cannot find an already healthy JARVIS.
/// A process we did not start is NEVER terminated or adopted for cleanup.
@MainActor
final class JarvisBundledServer: ObservableObject {
    @Published private(set) var message = "로컬 프로젝트 서버 확인 전"
    @Published private(set) var ready = false
    @Published private(set) var owner = "미확인"
    @Published private(set) var checking = false

    private var ownedProcess: Process?
    private var runningCheck = false
    private var shuttingDown = false
    private static let endpoint = URL(string: "http://127.0.0.1:8765/api/diagnostics")!

    static func validDiagnostics(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["scope"] as? String == "local_read_only",
              let server = object["server"] as? [String: Any],
              server["status"] as? String == "reachable",
              server["host"] as? String == "127.0.0.1",
              server["port"] as? Int == 8765 else {
            return false
        }
        return true
    }

    /// Rejects all externally supplied or ambiguous paths; only the packaged
    /// resources underneath Contents/Resources qualify as server program files.
    static func validResourceDirectory(_ directory: URL) -> Bool {
        guard directory.isFileURL,
              FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("app.py").path),
              FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("jarvis/server.py").path),
              FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("web/index.html").path)
        else { return false }
        return true
    }

    /// A conservative interpreter selection. Never evals shell text or runs
    /// arbitrary launch commands. Python 3 is required by the packaged code.
    static func pythonPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3", "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    /// Paid remote model flags are disabled for the app-managed process;
    /// explicit external API opt-in remains a separate, manual server workflow.
    static func safeEnvironment(from inherited: [String: String]) -> [String: String] {
        var env = inherited
        for key in [
            "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
            "JARVIS_ENABLE_BRAIN_API", "JARVIS_ENABLE_VISION_API",
            "JARVIS_ENABLE_DESIGN_API", "JARVIS_BRAIN_MODEL",
            "JARVIS_DB", "PYTHONPATH", "PYTHONHOME", "PYTHONSTARTUP"
        ] {
            env.removeValue(forKey: key)
        }
        env["JARVIS_NO_BROWSER"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONNOUSERSITE"] = "1"
        return env
    }

    private func checkHealth() async -> Bool {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 1.8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count < 180_000 else { return false }
            return Self.validDiagnostics(data)
        } catch {
            return false
        }
    }

    func connectOnLaunch() async {
        guard !runningCheck, !shuttingDown else { return }
        runningCheck = true
        checking = true
        defer {
            runningCheck = false
            checking = false
        }
        ready = false
        message = "로컬 서버 연결 확인 중"

        if await checkHealth() {
            ready = true
            owner = ownedProcess == nil ? "이미 실행 중인 서버" : "앱 내부 서버"
            message = "자비스 로컬 서버 연결됨 · \(owner) · 127.0.0.1 전용"
            return
        }

        // A previous managed process must not cause another Python server
        // to be launched during a transient HTTP failure.
        if let ownedProcess, ownedProcess.isRunning {
            message = "앱 내부 서버 응답이 없습니다. 다른 서버를 중복 실행하지 않았습니다."
            return
        }
        guard let resources = Bundle.main.resourceURL,
              Self.validResourceDirectory(resources) else {
            message = "앱 안에 로컬 서버 파일이 없습니다. 개발 폴더가 아닌 설치 앱을 실행해 주세요."
            return
        }
        guard let interpreter = Self.pythonPath() else {
            message = "Python 3 실행 파일이 없어 서버를 시작하지 못했습니다."
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: interpreter)
        process.arguments = ["-B", "app.py"]
        process.currentDirectoryURL = resources
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = Self.safeEnvironment(from: ProcessInfo.processInfo.environment)
        do {
            try process.run()
        } catch {
            message = "앱 내부 서버 실행 실패: \(error.localizedDescription)"
            return
        }
        ownedProcess = process
        owner = "앱 내부 서버"
        message = "자비스 내부 서버 시작 중 · 외부 API 사용 안 함"

        for _ in 0..<24 {
            if shuttingDown { return }
            if await checkHealth() {
                // A stranger could start a listener during our startup race.
                // Claim ownership only when OUR process is still running.
                if process.isRunning {
                    ready = true
                    message = "자비스 로컬 서버 연결됨 · 앱 내부 서버 · 127.0.0.1 전용"
                } else {
                    owner = "이미 실행 중인 서버"
                    ready = true
                    message = "로컬 자비스 서버 연결됨 · 앱 내부 서버는 종료됨"
                }
                return
            }
            if !process.isRunning {
                message = "로컬 서버가 종료됐습니다. 포트 8765 중복 또는 Python 오류를 확인해 주세요."
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        message = "로컬 서버 응답이 없습니다. 자동 재시작이나 다른 프로세스 종료는 하지 않았습니다."
    }

    func stopOwnedServer() {
        shuttingDown = true
        ready = false
        guard let process = ownedProcess else { return }
        ownedProcess = nil
        if process.isRunning {
            process.terminate()
        }
    }
}

@MainActor
final class JarvisAppLifecycle: NSObject, NSApplicationDelegate {
    let server = JarvisBundledServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await server.connectOnLaunch() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stopOwnedServer()
    }
}
