import Foundation

func assertContains(_ actual: String, _ expected: String) {
    precondition(actual.contains(expected), "Expected \(expected) in: \(actual)")
}

func assertIntent(_ input: String, _ expected: EIDISIntent) {
    let actual = EIDISCommand.intent(for: input)
    precondition(actual == expected, "Intent mismatch for '\(input)': \(actual)")
}

assertIntent("애기야", .greeting)
assertIntent("아기야", .greeting)
assertIntent("애기", .greeting)
assertIntent("애기야 안녕", .greeting)
assertIntent("애기야, 오늘 날씨 알려줘", .weather)
assertIntent("아기야 오늘 기온은", .weather)
assertIntent("애기야 오늘 일정 뭐야", .calendar)
assertIntent("애기야 다음 회의", .calendar)
assertIntent("애기야 오늘 할 일", .reminders)
assertIntent("애기야 미리 알림 보여 줘", .reminders)
assertIntent("애기야 뭐 할 수 있어", .help)
assertIntent("애기야 Mac 프로젝트", .unsupported)
assertIntent("카메라 켜줘", .unknown)
assertIntent("", .unknown)

assertContains(JARVISResponse.answer(to: ""), "음성으로")
assertContains(JARVISResponse.answer(to: "애기야"), "네, 말씀하세요")
assertContains(JARVISResponse.answer(to: "애기야 날씨"), "날씨 카드를 눌러")
assertContains(JARVISResponse.answer(to: "애기야 일정"), "캘린더를 연결")
assertContains(JARVISResponse.answer(to: "애기야 할 일"), "미리 알림")
assertContains(JARVISResponse.answer(to: "이거 뭐야"), "지원하지 않는")
precondition(!JARVISResponse.answer(to: "애기야 일정").contains("09:30"))
precondition(!JARVISResponse.answer(to: "애기야 날씨").contains("°C"))
precondition(EIDISCommand.hints.contains("애기야"))
print("PASS: EIDIS Korean invocation phrases, grounded routes, and offline fallback")
