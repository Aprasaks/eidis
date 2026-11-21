import Foundation

@main
struct BrowserControlSmoke {
    static func main() {
        func expect(_ spoken: String, _ expected: JarvisBrowserControlIntent?) {
            let actual=JarvisBrowserControlIntent.parse(spoken)
            precondition(actual==expected, "Intent mismatch: \(spoken); got \(String(describing:actual))")
        }
        expect("자비스, 브라우저에서 https://www.python.org/ 열어줘",
               .open(URL(string:"https://www.python.org/")!))
        expect("자비스, https://docs.python.org/3/ 열어줘",
               .open(URL(string:"https://docs.python.org/3/")!))
        expect("자비스, 링크 목록 보여줘", .links)
        expect("자비스, 링크 2번 열어줘",.follow(2))
        expect("자비스, 링크 12번 클릭해줘",.follow(12))
        expect("자비스, 검색창에 Python documentation 입력해줘",.typeSearch("Python documentation"))
        expect("자비스, 스크롤 내려줘",.scrollDown)
        expect("자비스, 스크롤 올려줘",.scrollUp)
        expect("자비스, 현재 페이지 확인해줘",.inspect)
        for bad in ["자비스, 링크 2번 열어줘?", "자비스, 링크 2번 클릭하지마",
                    "자비스, https://localhost/ 열어줘",
                    "자비스, https://127.0.0.1/ 열어줘",
                    "자비스, http://example.com/ 열어줘",
                    "자비스, https://example.com:8765/ 열어줘",
                    "자비스, https://user:password@example.com/ 열어줘",
                    "자비스, 검색창에 비밀번호:secret 입력해줘",
                    "자비스, 검색창에 someone@example.com 입력해줘",
                    "자비스, 검색창에 거기에 otp 입력해줘",
                    "자비스, 페이지에서 결제 클릭해줘",
                    "자비스, 크롬에서 쿠팡 결제해줘",
                    "자비스, 링크 99번 열어줘"] {
            precondition(JarvisBrowserControlIntent.parse(bad)==nil,bad)
        }
        let home=URL(string:"https://www.python.org/")!
        let docs=URL(string:"https://www.python.org/doc/")!
        precondition(JarvisBrowserControlPolicy.safeReadOnlyLink(docs,from:home))
        for dangerous in [
            "https://docs.python.org/3/",
            "https://www.python.org/logout",
            "https://www.python.org/account/delete",
            "https://www.python.org/download?token=123",
            "https://www.python.org/purchase",
            "https://www.python.org/?action=unsubscribe",
            "https://www.python.org/checkout",
            "https://127.0.0.1/",
            "https://169.254.169.254/",
            "https://localhost/admin",
            "http://www.python.org/",
            "https://www.python.org:1234/",
            "https://www.python.org/oauth/callback"
        ] {
            let u=URL(string:dangerous)!
            precondition(!JarvisBrowserControlPolicy.safeReadOnlyLink(u,from:home),
                         "Unexpectedly accepted: \(dangerous)")
        }
        print("PASS: explicit browser controls, URL restrictions, same-host navigation, no form submission")
    }
}
