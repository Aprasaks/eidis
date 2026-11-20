import Foundation

/// Existing Vercel CLI login is used for read-only project and deployment status.
struct JarvisVercelProject: Decodable, Identifiable, Sendable {
    let name: String
    let id: String
    let latestProductionUrl: String?
}

struct JarvisVercelDeployment: Decodable, Identifiable, Sendable {
    let url: String
    let name: String
    let state: String?
    let target: String?
    let createdAt: Int64?
    var id: String { url }
}

struct JarvisVercelSnapshot: Sendable {
    let projects: [JarvisVercelProject]
    let deployments: [JarvisVercelDeployment]
    let accountScope: String?
    let hasMoreDeployments: Bool
    let checkedAt: Date
    let error: String?
}

enum JarvisVercelRemoteScanner {
    private struct ProjectReply: Decodable {
        let projects: [JarvisVercelProject]
        let contextName: String?
    }
    private struct Page: Decodable { let next: Int64? }
    private struct DeploymentReply: Decodable {
        let deployments: [JarvisVercelDeployment]
        let contextName: String?
        let pagination: Page?
    }

    nonisolated static func scan() -> JarvisVercelSnapshot {
        guard let cli = findCLI() else { return failure("Vercel CLI가 설치되어 있지 않습니다.") }
        // Fixed read commands, never project mutation or deployment.
        guard let projectsData = readCLI(cli, args: ["project", "ls", "--format=json"]),
              let projectsReply = try? JSONDecoder().decode(ProjectReply.self, from: projectsData) else {
            return failure("Vercel 프로젝트 조회에 실패했습니다. 로그인과 네트워크를 확인해 주세요.")
        }
        guard let deployData = readCLI(cli, args: ["ls", "--format=json"]),
              let deployReply = try? JSONDecoder().decode(DeploymentReply.self, from: deployData) else {
            return JarvisVercelSnapshot(projects: projectsReply.projects, deployments: [],
                    accountScope: projectsReply.contextName, hasMoreDeployments: false,
                    checkedAt: Date(), error: "최근 배포 목록 조회에 실패했습니다.")
        }
        return JarvisVercelSnapshot(projects: projectsReply.projects,
            deployments: deployReply.deployments,
            accountScope: projectsReply.contextName,
            hasMoreDeployments: deployReply.pagination?.next != nil,
            checkedAt: Date(), error: nil)
    }

    private nonisolated static func findCLI() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var candidates = ["/opt/homebrew/bin/vercel", "/usr/local/bin/vercel"]
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fm.contentsOfDirectory(at: nvm,
                 includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            candidates += versions.sorted(by: { $0.path > $1.path })
                .map { $0.appendingPathComponent("bin/vercel").path }
        }
        return candidates.first(where: { fm.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    private nonisolated static func readCLI(_ executable: URL, args: [String]) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = executable.deletingLastPathComponent().path + ":" +
                      (env["PATH"] ?? "/usr/bin:/bin")
        env["CI"] = "1"
        env["VERCEL_DISABLE_UPDATE_CHECK"] = "1"
        env["NO_COLOR"] = "1"
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20,
                                                        execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return process.terminationStatus == 0 && data.count <= 2_000_000 ? data : nil
    }

    private static func failure(_ message: String) -> JarvisVercelSnapshot {
        JarvisVercelSnapshot(projects: [], deployments: [], accountScope: nil,
                              hasMoreDeployments: false, checkedAt: Date(), error: message)
    }
}
