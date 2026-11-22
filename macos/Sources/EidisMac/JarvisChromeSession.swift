import AppKit
import Foundation

/// Opens an explicitly approved DECHIVE channel in the user's existing Google
/// Chrome installation, rather than a new unauthenticated WebKit session.
///
/// Never reads cookies, passwords, browsing history, files, localStorage or
/// Chrome profile directories. No Chrome remote-debugging endpoint is enabled.
@MainActor
final class JarvisChromeSession: ObservableObject {
    @Published private(set) var status = "Chrome 연결 대기"
    @Published private(set) var lastOpenedChannel: JarvisSocialProfile?
    @Published private(set) var connectionStatus = "Chrome 세션 확인 전 · 연결 승인 필요"
    @Published private(set) var connectedChannels: [String] = []
    @Published private(set) var isChecking = false

    private struct BridgeResult: Decodable {
        let connected: Bool
        let channels: [String]
        let error: String?
    }

    /// Optional read-only DevTools check. Runs only after a direct button tap.
    /// It can list pages internally, but reports ONLY known DECHIVE channels.
    func checkExistingChromeTabs() async {
        guard !isChecking else { return }
        isChecking = true
        connectionStatus = "Chrome 연결 승인 확인 중 · Chrome 허용 창이 뜨면 직접 승인하세요"
        defer { isChecking = false }
        guard let script = Bundle.main.resourceURL?
                .appendingPathComponent("chrome-bridge/check.mjs"),
              FileManager.default.fileExists(atPath: script.path),
              let node = Self.nodeExecutable() else {
            connectionStatus = "Chrome 연결 모듈 또는 Node.js를 찾지 못했습니다"
            return
        }
        guard let data = await Self.runReadOnlyBridge(node: node, script: script),
              data.count < 4096,
              let result = try? JSONDecoder().decode(BridgeResult.self, from: data) else {
            connectionStatus = "Chrome 연결 확인 실패 · 원격 디버깅 설정과 허용 여부를 확인하세요"
            return
        }
        guard result.connected else {
            connectionStatus = "Chrome 연결 대기 · chrome://inspect/#remote-debugging 설정과 승인 필요"
            connectedChannels = []
            return
        }
        let authorized = Set(["instagram", "threads", "facebook", "youtube"])
        connectedChannels = Array(Set(result.channels).intersection(authorized)).sorted()
        if connectedChannels.isEmpty {
            connectionStatus = "Chrome 접근 확인 · DECHIVE SNS 탭은 열려 있지 않음"
        } else {
            connectionStatus = "Chrome 접근 확인 · DECHIVE 탭 \(connectedChannels.count)개 확인"
        }
    }

    private static func nodeExecutable() -> URL? {
        let manager = FileManager.default
        let fixed = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        let versions = NSHomeDirectory() + "/.nvm/versions/node"
        let discovered = (try? manager.contentsOfDirectory(atPath: versions))?
            .sorted(by: >).map { versions + "/" + $0 + "/bin/node" } ?? []
        return (fixed + discovered).first(where: { manager.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    nonisolated private static func runReadOnlyBridge(node: URL, script: URL) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = node
                task.arguments = [script.path]
                task.currentDirectoryURL = script.deletingLastPathComponent()
                task.environment = [
                    "HOME": NSHomeDirectory(),
                    "PATH": node.deletingLastPathComponent().path + ":/usr/bin:/bin",
                    "LANG": "en_US.UTF-8",
                    "TMPDIR": NSTemporaryDirectory(),
                    "CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS": "1",
                    "CHROME_DEVTOOLS_MCP_NO_PERFORMANCE_CRUX": "1",
                    "JARVIS_CHROME_CHECK_TIMEOUT_MS": "35000"
                ]
                let output = Pipe()
                task.standardOutput = output
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                    // Always bound the adapter lifetime, including child-MCP stalls.
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 42) {
                        if task.isRunning { task.terminate() }
                    }
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()
                    continuation.resume(returning: data.count <= 4096 ? data : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }


    private var workspaceWindowID: Int?
    /// Open or reuse only the dedicated Chrome workspace window. The existing
    /// browser profile handles authentication; unrelated windows are untouched.
    func openWorkspace(_ channel: JarvisSocialProfile, youtubeChannelID: String?,
                       chromeBounds: CGRect) async -> Bool {
        guard let url = channel.url(youtubeChannelID: youtubeChannelID),
              Self.isApprovedSocialURL(url, channel: channel, youtubeChannelID: youtubeChannelID) else {
            status = OpenError.unsafeURL.localizedDescription
            return false
        }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil else {
            status = OpenError.missingChrome.localizedDescription
            return false
        }
        status = "Chrome 작업 공간 열기 요청 중"
        let id = await Self.placeChromeWindow(url: url, bounds: chromeBounds, reuseID: workspaceWindowID)
        guard let id else {
            status = "Chrome 작업 공간을 열지 못했습니다. macOS 자동화 권한과 Chrome 창 상태를 확인하세요."
            return false
        }
        workspaceWindowID = id
        lastOpenedChannel = channel
        status = "Chrome 작업 공간 열림 · 로그인 상태는 화면에서 확인"
        return true
    }

    nonisolated private static func placeChromeWindow(url: URL, bounds: CGRect, reuseID: Int?) async -> Int? {
        let script = """
        on run argv
            set targetURL to item 1 of argv
            set wantedID to (item 2 of argv) as integer
            set wantedBounds to {(item 3 of argv) as integer, (item 4 of argv) as integer, (item 5 of argv) as integer, (item 6 of argv) as integer}
            tell application "Google Chrome"
                set workWindow to missing value
                if wantedID is greater than 0 then
                    if exists (window id wantedID) then set workWindow to window id wantedID
                end if
                if workWindow is missing value then
                    set workWindow to make new window
                    set URL of active tab of workWindow to targetURL
                else
                    set matchIndex to 0
                    repeat with tabIndex from 1 to count of tabs of workWindow
                        if URL of tab tabIndex of workWindow is targetURL then
                            set matchIndex to tabIndex
                            exit repeat
                        end if
                    end repeat
                    if matchIndex is 0 then
                        make new tab at end of tabs of workWindow with properties {URL:targetURL}
                        set matchIndex to count of tabs of workWindow
                    end if
                    set active tab index of workWindow to matchIndex
                end if
                set bounds of workWindow to wantedBounds
                set index of workWindow to 1
                activate
                return (id of workWindow) as text
            end tell
        end run
        """
        let args = ["-e", script, "--", url.absoluteString, String(reuseID ?? 0),
                    String(Int(bounds.minX)), String(Int(bounds.minY)),
                    String(Int(bounds.maxX)), String(Int(bounds.maxY))]
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = args
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 45) {
                        if process.isRunning { process.terminate() }
                    }
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: process.terminationStatus == 0 ? value.flatMap(Int.init) : nil)
                } catch { continuation.resume(returning: nil) }
            }
        }
    }

    enum OpenError: LocalizedError {
        case missingChrome
        case unsafeURL
        var errorDescription: String? {
            switch self {
            case .missingChrome: "Google Chrome이 설치되어 있지 않습니다."
            case .unsafeURL: "DECHIVE에서 승인한 공식 SNS 주소가 아닙니다."
            }
        }
    }

    /// Only exact pinned profile URLs from JarvisSocialProfile may open.
    func open(_ channel: JarvisSocialProfile, youtubeChannelID: String?) async -> Bool {
        guard let url = channel.url(youtubeChannelID: youtubeChannelID),
              Self.isApprovedSocialURL(url, channel: channel,
                                       youtubeChannelID: youtubeChannelID) else {
            status = OpenError.unsafeURL.localizedDescription
            return false
        }
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
              chrome.isFileURL else {
            status = OpenError.missingChrome.localizedDescription
            return false
        }
        status = "기존 Chrome 로그인 세션에서 \(channel.title) 열기 요청 중"
        do {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.open([url], withApplicationAt: chrome,
                                        configuration: config) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            lastOpenedChannel = channel
            // Opening a URL proves handoff, NOT that a user is logged in.
            status = "Chrome에 \(channel.title) 주소 전달 완료 · 로그인 상태는 화면에서 확인"
            return true
        } catch {
            status = "Chrome에서 프로필 열기 실패: \(error.localizedDescription)"
            return false
        }
    }

    static func isApprovedSocialURL(_ url: URL, channel: JarvisSocialProfile,
                                    youtubeChannelID: String?) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil, url.fragment == nil,
              let exact = channel.url(youtubeChannelID: youtubeChannelID) else { return false }
        return url.absoluteString == exact.absoluteString
    }
}
