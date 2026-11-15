import Foundation

func assertContains(_ actual: String, _ expected: String) {
    precondition(actual.contains(expected), "Expected \(expected) in response: \(actual)")
}

assertContains(EIDISResponse.answer(to: ""), "음성으로")
assertContains(EIDISResponse.answer(to: "이디스, 안녕"), "안녕하세요. 이디스입니다.")
assertContains(EIDISResponse.answer(to: "좋은 아침"), "안녕하세요")
assertContains(EIDISResponse.answer(to: "지금 뭐 할 수 있어?"), "기본 음성 응답")
assertContains(EIDISResponse.answer(to: "자비스, 다음 할 일 뭐야?"), "아직 iPhone과 동기화되지")
assertContains(EIDISResponse.answer(to: "오늘 날씨 알려줘"), "아직 연결되지")
assertContains(EIDISResponse.answer(to: "이거 뭐야?"), "아직 연결되지")
assertContains(EIDISResponse.answer(to: "응답해봐"), "개인 AI 연결을 준비")
precondition(!EIDISResponse.answer(to: "오늘 일정 보여줘").contains("09:30"))
precondition(!EIDISResponse.answer(to: "이번 주 날씨").contains("°C"))
print("PASS EIDIS Korean local replies grounded; no fake weather/schedule, no fabricated Mac sync")
