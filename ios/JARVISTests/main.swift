import Foundation

@main
struct JARVISMobileIntentTests {
    static func main() {
        let examples: [(String, JARVISIntent)] = [
            ("애기야", .greeting),
            ("자비스 안녕", .greeting),
            ("맥북 상태 알려줘", .macStatus),
            ("맥북 켜줘", .macWake),
            ("아까 그 국내 미국 주식 현황표 열어봐", .stockBoard),
            ("애기야 주식 현황표", .stockBoard),
            ("뭐 할 수 있어?", .help),
            ("이해할 수 없는 요청", .unavailable),
        ]
        for (phrase, intent) in examples {
            precondition(JARVISCommand.intent(for: phrase) == intent,
                         "Incorrect offline intent: \(phrase)")
        }
        for phrase in ["맥북 켜줘", "주식 현황표 열어봐", "맥북 상태 알려줘"] {
            let response = JARVISCommand.response(to: phrase)
            precondition(response.contains("연결 전") ||
                         response.contains("연결되지") ||
                         response.contains("연결한 후"),
                         "Unverified remote success message for \(phrase)")
        }
        precondition(JARVISCommand.response(to: "애기야") .contains("오라버니"))
        print("PASS: 8 iOS local intent examples and 3 no-fake-remote-succcess assertions")
    }
}
