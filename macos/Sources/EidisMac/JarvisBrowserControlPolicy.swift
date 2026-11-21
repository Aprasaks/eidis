import Foundation

/// Strict, deterministic browser actions. This policy does not execute a
/// generated instruction, infer a URL or browse existing Chrome/Safari tabs.
enum JarvisBrowserControlIntent: Equatable {
    case open(URL)
    case links
    case follow(Int)
    case typeSearch(String)
    case scrollDown
    case scrollUp
    case inspect

    static func parse(_ phrase: String) -> Self? {
        let spoken = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(자비스|jarvis)[,，.!\s]*"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = spoken.replacingOccurrences(of: " ", with: "")
        let clean = normalized.trimmingCharacters(in: CharacterSet(charactersIn: ".!！"))
        guard !spoken.contains("?"), !spoken.contains("？"),
              !["하지마","하지말","하지않","하지않아","입력하지","클릭하지","열지마","이건취소",
                "취소해","그만","삭제","결제","구매"].contains(where: {clean.contains($0)}) else {
            return nil
        }

        if ["브라우저링크목록보여줘","링크목록보여줘","이페이지링크보여줘",
            "현재페이지링크보여줘","여기링크알려줘","브라우저링크보여줘"].contains(clean) {
            return .links
        }
        if ["현재페이지확인해줘","브라우저상태확인해줘","페이지상태알려줘",
            "지금어느페이지야","열린페이지확인해줘"].contains(clean) {
            return .inspect
        }
        if ["스크롤내려줘","페이지아래로내려줘","아래로스크롤해줘"].contains(clean) {
            return .scrollDown
        }
        if ["스크롤올려줘","페이지위로올려줘","위로스크롤해줘"].contains(clean) {
            return .scrollUp
        }
        if clean.range(of: #"^링크[1-9][0-9]?번(열어줘|이동해줘|클릭해줘)$"#,
                       options: .regularExpression) != nil,
           let digits = clean.range(of: #"[1-9][0-9]?"#, options: .regularExpression),
           let id = Int(clean[digits]), id <= 12 {
            return .follow(id)
        }
        let inputPrefix = ["검색창에","검색필드에","브라우저검색창에"]
        for prefix in inputPrefix where spoken.hasPrefix(prefix) {
            let tail = spoken.dropFirst(prefix.count).trimmingCharacters(in:.whitespacesAndNewlines)
            for ending in ["입력해줘","입력해봐","써줘"] where tail.hasSuffix(ending) {
                let value=tail.dropLast(ending.count).trimmingCharacters(in:.whitespacesAndNewlines)
                if isSafeSearchInput(value) { return .typeSearch(value) }
            }
        }
        // Explicit address only; an inferred search string is never a URL.
        let prefixes=["브라우저에서 ", "브라우저로 ", "주소 ", "사이트 "]
        var remainder=spoken
        for prefix in prefixes where remainder.hasPrefix(prefix) {
            remainder=String(remainder.dropFirst(prefix.count))
            break
        }
        for suffix in [" 열어줘"," 열어봐"," 접속해줘"," 이동해줘"] where remainder.hasSuffix(suffix) {
            let address=String(remainder.dropLast(suffix.count))
                .trimmingCharacters(in:.whitespacesAndNewlines)
            if let url=URL(string:address), JarvisBrowserControlPolicy.safePublicURL(url),
               address.lowercased().hasPrefix("https://") {
                return .open(url)
            }
        }
        return nil
    }

    private static func isSafeSearchInput(_ value: String) -> Bool {
        guard 1...120 ~= value.count, !value.contains("\n"), !value.contains("\r"),
              !value.contains("@") else { return false }
        let lower=value.lowercased().replacingOccurrences(of:" ",with:"")
        return !["password","비밀번호","otp","api_key","token=","secret","creditcard","카드번호",
                 "주민등록번호","계좌번호"].contains(where:{lower.contains($0)})
    }
}

enum JarvisBrowserControlPolicy {
    // All automatic navigations use a public HTTPS origin and port 443.
    // This is a URL syntax restriction, NOT a DNS/response sandbox.
    static func safePublicURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased()=="https", url.user==nil, url.password==nil,
              url.port==nil || url.port==443, url.absoluteString.count<=1500,
              let host=url.host?.lowercased(), host.count<=253, host.contains("."),
              !host.hasPrefix("."), !host.hasSuffix("."),
              !["localhost","localhost.localdomain"].contains(host),
              ![".local",".localhost",".internal",".test",".invalid",".lan",
                 ".home",".onion",".arpa",".localdomain",".nip.io",".sslip.io",
                 ".localtest.me",".lvh.me",".xip.io"].contains(where:{host.hasSuffix($0)}) else {
            return false
        }
        let labels=host.split(separator:".")
        guard labels.count>=2, labels.allSatisfy({
            !$0.isEmpty && $0.count<=63 && $0.first != "-" && $0.last != "-" &&
            $0.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber || $0=="-")})
        }),
        let suffix=labels.last, suffix.count>=2 && suffix.contains(where:{$0.isLetter}),
        !host.contains(".."), !host.contains("127.0.0.1"),
        !host.contains("169.254."), !host.contains("0x7f") else { return false }
        return true
    }

    /// Non-idempotent GET paths are excluded even when disguised as links.
    static func safeReadOnlyLink(_ url: URL, from page: URL) -> Bool {
        guard safePublicURL(url), safePublicURL(page),
              url.host?.lowercased()==page.host?.lowercased() else { return false }
        if url.fragment != nil || url.absoluteString==page.absoluteString ||
           url.absoluteString.lowercased().contains("%25") {
            return false
        }
        let path=url.path.removingPercentEncoding?.lowercased() ?? url.path.lowercased()
        let query=url.query?.removingPercentEncoding?.lowercased() ?? url.query?.lowercased() ?? ""
        let denied=["logout","log-out","signout","sign-out","delete","remove",
                    "purchase","checkout","payment","unsubscribe","submit",
                    "admin","oauth","account","billing","cart","order","auth"]
        let parts=path.split(separator:"/").map(String.init)
        if parts.contains(where:{denied.contains($0)}) { return false }
        let suspicious=["action=","method=","delete","logout","remove","unsubscribe",
                        "checkout","purchase","payment","token=","key="]
        if suspicious.contains(where:{query.contains($0)}) { return false }
        return true
    }
}
