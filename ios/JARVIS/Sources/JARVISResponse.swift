import Foundation

/// Offline fallback. Personal facts are only spoken from authorized services
/// in EIDISHomeView and never fabricated by the fallback text.
enum JARVISResponse {
    static func answer(to input: String) -> String {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "음성으로 말씀해 주세요."
        }
        switch EIDISCommand.intent(for: input) {
        case .greeting:
            return "네, 말씀하세요. 애기야라고 부르면 알아들을 수 있어요."
        case .weather:
            return "날씨 카드를 눌러 실제 현재 위치의 날씨를 연결해 주세요."
        case .calendar:
            return "일정 카드를 눌러 iPhone 캘린더를 연결해 주세요."
        case .reminders:
            return "오늘의 작업 카드를 눌러 iPhone 미리 알림을 연결해 주세요."
        case .help:
            return "애기야 날씨, 애기야 일정, 애기야 할 일이라고 말해 보세요. 마이크 버튼을 눌러야 듣습니다."
        case .unsupported:
            return "개인 AI, Mac 프로젝트 기억과 카메라 장면 분석은 아직 연결되지 않았어요."
        case .unknown:
            return "말씀은 인식했지만 아직 지원하지 않는 요청입니다. 개인 AI 연결은 다음 단계입니다."
        }
    }
}
