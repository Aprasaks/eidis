import Foundation

/// Exact-label, read-only navigation controls only. No generic AXPress.
enum JarvisSafePressPolicy {
    static func allows(role: String, label: String) -> Bool {
        guard role == "AXButton" else { return false }
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return [
            "새로고침", "새로 고침", "페이지 새로고침", "새로 고침하기",
            "refresh", "reload", "reload this page",
            "reload page", "refresh page"
        ].contains(normalized)
    }

    static let explanation = "새로고침만 허용합니다. 미저장 입력은 사라질 수 있으니 확인하세요. 삭제·전송·결제·발행 버튼은 실행할 수 없습니다."
}
