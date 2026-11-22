import Foundation

/// Only explicitly named DECHIVE channels can be opened by voice.
/// The destination is pinned to a known official profile, never inferred by a model.
enum JarvisSocialProfile: String, CaseIterable {
    case instagram, threads, facebook, youtube

    var title: String {
        switch self {
        case .instagram: return "Instagram · @dechive.wiki"
        case .threads: return "Threads · @dechive.wiki"
        case .facebook: return "Facebook · Dechive WIKI"
        case .youtube: return "YouTube · DECHIVE"
        }
    }

    func url(youtubeChannelID: String? = nil) -> URL? {
        switch self {
        case .instagram: return URL(string: "https://www.instagram.com/dechive.wiki/")
        case .threads: return URL(string: "https://www.threads.com/@dechive.wiki")
        case .facebook: return URL(string: "https://www.facebook.com/profile.php?id=1433547446509432")
        case .youtube:
            guard let id = youtubeChannelID, (10...60).contains(id.count),
                  id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { return nil }
            return URL(string: "https://www.youtube.com/channel/\(id)")
        }
    }

    static func parse(_ phrase: String) -> Self? {
        let lower = phrase.lowercased()
        let cleaned = lower.replacingOccurrences(of: #"^(자비스|데카|jarvis)[,，.!?\s]*"#,
                                                  with: "", options: .regularExpression)
            .filter { !$0.isWhitespace && !$0.isNewline }
        guard ["열어", "띄워", "보여", "켜줘", "접속해", "들어가"].contains(where: { cleaned.contains($0) }),
              !["대시보드", "현황", "통계", "분석", "검색", "찾아", "비교", "뉴스", "로그인", "광고", "게시", "댓글", "삭제", "취소", "하지마", "열지마"].contains(where: { cleaned.contains($0) }) else { return nil }
        if ["인스타그램", "인스타", "instagram"].contains(where: { cleaned.contains($0) }) { return .instagram }
        if ["스레드", "threads"].contains(where: { cleaned.contains($0) }) { return .threads }
        if ["페이스북", "페북", "facebook"].contains(where: { cleaned.contains($0) }) { return .facebook }
        if ["유튜브", "youtube"].contains(where: { cleaned.contains($0) }) { return .youtube }
        return nil
    }
}
