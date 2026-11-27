import Foundation

/// Explicit web requests only. Do not confuse local file/project lookup with
/// searching the public internet, and never turn a web page into a shell action.
enum JarvisWebIntent: Equatable {
    case search(String, engine: SearchEngine)
    case hide

    enum SearchEngine: Equatable {
        case naver, google
        var title: String { self == .naver ? "네이버" : "Google" }
        func url(for query: String) -> URL? {
            guard !query.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            switch self {
            case .naver:
                // Compact search results fit the right-side JARVIS panel.
                components.host = "m.search.naver.com"
                components.path = "/search.naver"
                components.queryItems = [URLQueryItem(name: "query", value: query)]
            case .google:
                components.host = "www.google.com"
                components.path = "/search"
                components.queryItems = [URLQueryItem(name: "q", value: query)]
            }
            return components.url
        }
    }

    static func parse(_ phrase: String) -> Self? {
        let value = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let compact = value.lowercased().replacingOccurrences(of: " ", with: "")
        let browserWord = ["브라우저", "인터넷창", "웹페이지", "검색창", "검색결과", "인터넷검색"].contains {
            compact.contains($0)
        }
        let close = ["닫아", "닫기", "숨겨", "꺼줘", "치워", "없애"].contains { compact.contains($0) }
        if browserWord && close { return .hide }

        // Local-file and project searches have distinct execution paths and
        // must never silently transmit filenames or private data to a website.
        let local = ["내파일", "맥파일", "내문서", "다운로드폴더", "로컬파일", "폴더에서", "파일찾아",
                     "내프로젝트", "작업기록", "내작업", "메일에서", "이메일에서"].contains {
            compact.contains($0)
        }
        if local { return nil }
        let searchVerbs = ["검색해줘", "검색해", "찾아줘", "찾아봐", "찾아보자", "검색해봐", "조사해줘", "조사해봐"]
        guard searchVerbs.contains(where: { compact.contains($0) }) else { return nil }
        let engine: SearchEngine = compact.contains("구글") || compact.contains("google") ? .google : .naver
        var query = value
        let prefixes = ["이디스,", "이디스", "자비스,", "자비스", "인터넷에서", "웹에서", "네이버에서", "구글에서", "네이버로", "구글로", "인터넷으로", "인터넷 검색으로"]
        // Strip only command prefixes. A search query may itself contain
        // the word '자비스', which must not be deleted from the search terms.
        for _ in 0..<3 {
            query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let prefix = prefixes.first(where: { query.lowercased().hasPrefix($0.lowercased()) }) else { break }
            query = String(query.dropFirst(prefix.count))
        }
        let endings = ["검색해줘", "검색해봐", "검색해", "찾아줘", "찾아봐", "찾아보자", "조사해줘", "조사해봐"]
        // Remove command suffix only, preserving arbitrary search words.
        query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        for ending in endings {
            if query.hasSuffix(ending) {
                query = String(query.dropLast(ending.count))
                break
            }
        }
        query = query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !query.isEmpty else { return nil }
        return .search(String(query.prefix(180)), engine: engine)
    }
}
