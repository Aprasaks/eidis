import AppKit
import Foundation

func payload(_ scope: String, _ host: String, _ port: Int) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "scope": scope,
        "server": ["status": "reachable", "host": host, "port": port]
    ])
}
let valid = try payload("local_read_only", "127.0.0.1", 8765)
precondition(MainActor.assumeIsolated { JarvisBundledServer.validDiagnostics(valid) })
for data in [
    try payload("local_read_only", "127.0.0.1", 9000),
    try payload("local_read_only", "0.0.0.0", 8765),
    try payload("unrelated", "127.0.0.1", 8765),
    Data("invalid response".utf8)
] {
    precondition(!MainActor.assumeIsolated {
        JarvisBundledServer.validDiagnostics(data)
    })
}
let env = MainActor.assumeIsolated {
    JarvisBundledServer.safeEnvironment(from: [
        "OPENAI_API_KEY": "secret",
        "ANTHROPIC_API_KEY": "secret",
        "JARVIS_ENABLE_BRAIN_API": "1",
        "JARVIS_ENABLE_VISION_API": "1",
        "JARVIS_ENABLE_DESIGN_API": "1",
        "JARVIS_BRAIN_MODEL": "paid",
        "JARVIS_DB": "/tmp/wrong",
        "PYTHONPATH": "/tmp/unsafe",
        "PYTHONHOME": "/tmp/unsafe",
        "CUSTOM_SAFE_VALUE": "fine"
    ])
}
for key in [
    "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "JARVIS_ENABLE_BRAIN_API",
    "JARVIS_ENABLE_VISION_API", "JARVIS_ENABLE_DESIGN_API",
    "JARVIS_BRAIN_MODEL", "JARVIS_DB", "PYTHONPATH", "PYTHONHOME"
] {
    precondition(env[key] == nil, "Private value or opt-in leaked: \(key)")
}
precondition(env["CUSTOM_SAFE_VALUE"] == "fine")
precondition(env["JARVIS_NO_BROWSER"] == "1")
precondition(env["PYTHONNOUSERSITE"] == "1")
precondition(env["PYTHONDONTWRITEBYTECODE"] == "1")
if CommandLine.arguments.count > 1 {
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    precondition(MainActor.assumeIsolated {
        JarvisBundledServer.validResourceDirectory(root)
    })
    precondition(!MainActor.assumeIsolated {
        JarvisBundledServer.validResourceDirectory(root.appendingPathComponent("missing"))
    })
}
print("PASS bundled server: identity, no paid flags, safe resource structure")
