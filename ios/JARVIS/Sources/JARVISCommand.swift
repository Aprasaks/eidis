import Foundation

/// Offline-only intent routing for the first iPhone build.
/// No remote operation is reported successful until Mac pairing exists.
enum JARVISIntent: Equatable {
    case greeting
    case macStatus
    case macWake
    case stockBoard
    case help
    case unavailable
}

enum JARVISCommand {
    static let hints: [String] = [
        "애기야", "아기야", "이디스", "자비스",
        "애기야 안녕", "맥북 연결 상태", "맥북 켜줘",
        "주식 현황표 열어봐", "국내 미국 주식", "뭐 할 수 있어"
    ]

    static func intent(for raw: String) -> JARVISIntent {
        let normalized = String(raw.lowercased().filter {
            !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol
        })
        guard !normalized.isEmpty else { return .unavailable }

        if has(normalized, ["맥북켜", "맥켜", "맥북깨", "컴퓨터깨", "컴퓨터켜"]) {
            return .macWake
        }
        if has(normalized, ["주식", "증권", "코스피", "나스닥"]) {
            return .stockBoard
        }
        if has(normalized, ["맥북", "맥상태", "컴퓨터상태", "원격제어", "맥연결"]) {
            return .macStatus
        }
        if has(normalized, ["뭐할수", "뭘할수", "기능", "사용법", "도움"]) {
            return .help
        }
        if has(normalized, ["애기야", "아기야", "이디스", "자비스", "안녕"]) {
            return .greeting
        }
        return .unavailable
    }

    static func response(to input: String) -> String {
        switch intent(for: input) {
        case .greeting:
            return "네, DECHIVE. 아이폰 이디스예요. 지금은 기기 안에서 음성 인식과 대화 화면을 시험할 수 있어요."
        case .macStatus:
            return "DECHIVE, 맥 이디스와 아직 연결되지 않았어요. 연결이 완료되기 전에는 맥 상태를 알 수 없어요."
        case .macWake:
            return "DECHIVE, 맥 깨우기 기능은 아직 연결 전이에요. 명령을 실행한 것은 아니에요."
        case .stockBoard:
            return "DECHIVE, 주식 현황표는 맥과 연결한 후에 열 수 있도록 준비할게요. 아직 실제 시세를 가져오지 않았어요."
        case .help:
            return "현재는 금빛 3D 코어, 아이폰 음성 인식, 텍스트 입력과 로컬 응답이 준비되어 있어요. 맥 원격 연결은 다음 단계예요."
        case .unavailable:
            return "DECHIVE, 이 요청은 아직 아이폰 이디스에서 처리할 수 없어요. 맥 연결이나 추가 기능이 필요한지 확인해야 해요."
        }
    }

    private static func has(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: text.contains)
    }
}
