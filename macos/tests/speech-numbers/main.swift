import Foundation
let cases:[(String,String)] = [
 ("기온 0.7도, 체감 -2.3도입니다.", "기온 영 점 칠 도, 체감 마이너스 이 점 삼 도입니다."),
 ("2026-11-21 22:15 기준", "이천이십육 년 십일 월 이십일 일 오후 열 시 십오 분 기준"),
 ("습도 93.0%, 풍속 5.9 km/h", "습도 구십삼 점 영 퍼센트, 풍속 오 점 구 킬로미터 매시간"),
 ("72,000원, +1.25%, 1,234,567원", "칠만 이천 원, 플러스 일 점 이 오 퍼센트, 백이십삼만 사천오백육십칠 원"),
 ("10:00, 00:05, 12:30:20", "오전 열 시, 오전 열두 시 오 분, 오후 열두 시 삼십 분 이십 초"),
 ("005930", "영 영 오 구 삼 영"),
 ("10000원 100000000원", "만 원 일억 원"),
 ("v3.14.3 API2 https://example.com/2026/11/21 `x=42`", "v3.14.3 API2 https://example.com/2026/11/21 `x=42`"),
 ("2026-02-30, 25:99, 1.2.3, 2-5", "2026-02-30, 25:99, 1.2.3, 2-5"),
 ("2026-06-01 2026-10-01", "이천이십육 년 유월 일 일 이천이십육 년 시월 일 일"),
 ("DECHIVE 3개", "데카이브 세 개"),
 ("20건 21개 2시간 99명", "스무 건 스물한 개 두 시간 아흔아홉 명"),
 ("현재가 0.7.", "현재가 영 점 칠."),
 ("군산 2026-11-21 22:15 기준 날씨입니다. 대체로 맑음, 기온 0.7도, 체감 -2.3도입니다.", "군산 이천이십육 년 십일 월 이십일 일 오후 열 시 십오 분 기준 날씨입니다. 대체로 맑음, 기온 영 점 칠 도, 체감 마이너스 이 점 삼 도입니다.")
]
for (input,expected) in cases {
 let actual=KoreanSpeechText.normalize(input)
 guard actual==expected else { fatalError("\(input) -> \(actual) expected \(expected)") }
 precondition(KoreanSpeechText.normalize(actual)==actual)
}
print("PASS: \(cases.count) Korean speech normalization cases + idempotence")
