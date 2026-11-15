import Foundation

let correct = Data("""
{"action":"project_self_overview","executed":false,"brain_source":"local",
"text":"자비스 자신의 프로젝트 기록입니다. 완료 14, 예정 11."}
""".utf8)
let decoded = try JSONDecoder().decode(JarvisRoundTrip.ChatReply.self, from: correct)
precondition(JarvisRoundTrip.isConfirmed(decoded, selfProjectFound: true))
precondition(!JarvisRoundTrip.isConfirmed(decoded, selfProjectFound: false))
for sample in [
    #"{"action":"project_self_overview","executed":true,"brain_source":"local","text":"자비스 자신의 프로젝트 기록입니다."}"#,
    #"{"action":"project_named_overview","executed":false,"brain_source":"local","text":"자비스 자신의 프로젝트 기록입니다."}"#,
    #"{"action":"project_self_overview","executed":false,"brain_source":"remote","text":"자비스 자신의 프로젝트 기록입니다."}"#,
    #"{"action":"project_self_overview","executed":false,"brain_source":"local","text":"기록 없음"}"#
] {
    let reply = try JSONDecoder().decode(
        JarvisRoundTrip.ChatReply.self, from: Data(sample.utf8))
    precondition(!JarvisRoundTrip.isConfirmed(reply, selfProjectFound: true))
}
print("PASS false positives rejected: explicit project, no execution, local origin, content")

if CommandLine.arguments.contains("--live") {
    let finding = await JarvisRoundTrip.check()
    print("LOCAL LIVE STATUS:", finding.passed, finding.detail)
    precondition(finding.passed, "Loopback JARVIS eidis self-command did not round-trip")
}
