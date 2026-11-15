import Foundation

enum JARVISResponse {
    static func answer(to input: String) -> String {
        let sentence = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return "음성으로 말씀해 주세요." }
        let normalized = sentence.replacingOccurrences(of: " ", with: "")
        if normalized.contains("안녕") || normalized.contains("좋은아침") {
            return "안녕하세요. 자비스입니다. 카메라와 음성 인터페이스가 준비됐어요."
        }
        if normalized.contains("뭐할수") || normalized.contains("무엇을할수") {
            return "지금은 카메라 화면과 한국어 음성 인식, 기본 음성 응답을 지원해요. 개인 AI와 프로젝트 기억은 아직 연결 전이에요."
        }
        if normalized.contains("자비스") || normalized.contains("할일") || normalized.contains("프로젝트") {
            return "Mac 자비스의 프로젝트 기억은 아직 iPhone과 동기화되지 않았어요. 실제 기록인 것처럼 답하지 않겠습니다."
        }
        if normalized.contains("날씨") || normalized.contains("일정") ||
            normalized.contains("길안내") || normalized.contains("어디") ||
            normalized.contains("이거뭐") || normalized.contains("뭐야") {
            return "해당 실시간 정보나 카메라 영상 분석은 아직 연결되지 않았어요. 확인되지 않은 내용을 만들지 않겠습니다."
        }
        return "말씀하신 문장은 인식했어요. 아직은 기본 음성 응답만 가능합니다. 개인 AI 연결을 준비하고 있어요."
    }
}
