import Foundation

/// Deterministic, speech-only formatting. The displayed answer and source
/// values stay unchanged. No model request or new provider is needed.
enum KoreanSpeechText {
    private static let digits = ["영","일","이","삼","사","오","육","칠","팔","구"]
    private static let groups = ["","만","억","조","경"]
    private static let smallUnits = ["","십","백","천"]
    private static func digitWords(_ value: String) -> String {
        value.compactMap { $0.wholeNumberValue }.map { digits[$0] }.joined(separator:" ")
    }
    private static func integer(_ value: String) -> String {
        let s = value.replacingOccurrences(of:",",with:"")
        if s == "0" { return "영" }
        // Keep leading zero identifiers and numbers beyond supported magnitudes
        // digit-by-digit instead of silently dropping information or rounding.
        guard !s.hasPrefix("0"), s.count <= 20 else { return digitWords(s) }
        let a = Array(s.reversed()).compactMap { $0.wholeNumberValue }
        var result: [String] = []
        for start in stride(from: 0, to: a.count, by: 4) {
            var part = ""
            for i in stride(from: min(3,a.count-start-1), through:0, by:-1) {
                let d = a[start+i]
                if d == 0 { continue }
                part += (d == 1 && i > 0 ? "" : digits[d]) + smallUnits[i]
            }
            if !part.isEmpty {
                let unit = groups[start/4]
                result.insert((part == "일" && unit == "만" ? "" : part) + unit, at:0)
            }
        }
        return result.isEmpty ? "영" : result.joined(separator:" ")
    }
    private static func number(_ value: String) -> String {
        var s = value
        var sign = ""
        if s.hasPrefix("-") || s.hasPrefix("−") { sign = "마이너스 "; s.removeFirst() }
        else if s.hasPrefix("+") { sign = "플러스 "; s.removeFirst() }
        let parts = s.split(separator:".",omittingEmptySubsequences:false)
        guard let whole = parts.first, !whole.isEmpty else { return value }
        if parts.count == 2 {
            return sign + integer(String(whole)) + " 점 " + digitWords(String(parts[1]))
        }
        return sign + integer(s)
    }
    private static func counted(_ value:String, unit:String?) -> String {
        guard ["개","건","명","번","시간"].contains(unit ?? ""),
              let n=Int(value), (1...99).contains(n), !value.hasPrefix("0") else { return number(value) }
        let ones=["","한","두","세","네","다섯","여섯","일곱","여덟","아홉"]
        let tens=["","열","스물","서른","마흔","쉰","예순","일흔","여든","아흔"]
        if n==20 { return "스무" }
        return tens[n/10]+ones[n%10]
    }
    private static func hour(_ h: Int) -> String {
        ["열두","한","두","세","네","다섯","여섯","일곱","여덟","아홉","열","열한"][h % 12]
    }
    private static func clock(_ h:Int,_ m:Int,_ sec:Int?) -> String {
        var words = (h < 12 ? "오전 " : "오후 ") + hour(h) + " 시"
        if m != 0 || sec != nil { words += " " + integer(String(m)) + " 분" }
        if let sec { words += " " + integer(String(sec)) + " 초" }
        return words
    }
    // Match protected literals first. Avoid touching URLs, ASCII identifiers,
    // versions, fractions, dates we cannot validate, or numeric ranges.
    private static let tokens = try! NSRegularExpression(pattern:
        #"https?://[^\s]+|www\.[^\s]+|\x60[^\x60]*\x60|[A-Za-z_][A-Za-z_0-9./:-]*[0-9][A-Za-z_0-9./:-]*|(?<![A-Za-z0-9])([0-9]{4})-([0-9]{2})-([0-9]{2})(?![0-9])|(?<![A-Za-z0-9])([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?(?![0-9:])|[0-9]+(?:\.[0-9]+){2,}|[0-9]+(?:[-~/–—][0-9]+)+|(?<![A-Za-z0-9_.])([+−-]?(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?)(?:[ \t]*(°C|℃|°F|℉|km/h|m/s|KRW|USD|%|퍼센트|도|원|달러|킬로미터|미터|개|건|명|번|시간))?(?![A-Za-z0-9_]|\.[0-9])"#)
    static func normalize(_ text:String) -> String {
        let base=text.replacingOccurrences(of:"DECHIVE",with:"데카이브",options:.caseInsensitive)
        let ns=base as NSString
        var result=base
        for match in tokens.matches(in:base,range:NSRange(location:0,length:ns.length)).reversed() {
            func g(_ i:Int)->String? {
                let r=match.range(at:i)
                return r.location == NSNotFound ? nil : ns.substring(with:r)
            }
            var replacement:String?
            if let y=g(1).flatMap(Int.init),let m=g(2).flatMap(Int.init),let d=g(3).flatMap(Int.init) {
                var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(secondsFromGMT:0)!
                if y>0,let date=c.date(from:DateComponents(year:y,month:m,day:d)),
                   c.dateComponents([.year,.month,.day],from:date)==DateComponents(year:y,month:m,day:d) {
                    let month=m==6 ? "유월" : m==10 ? "시월" : integer(String(m))+" 월"
                    replacement=integer(String(y))+" 년 "+month+" "+integer(String(d))+" 일"
                }
            } else if let h=g(4).flatMap(Int.init),let m=g(5).flatMap(Int.init) {
                let sec=g(6).flatMap(Int.init)
                if h<24,m<60,(sec ?? 0)<60 { replacement=clock(h,m,sec) }
            } else if let n=g(7) {
                let u=g(8)
                let units=["°C":"도","℃":"도","°F":"화씨 도","℉":"화씨 도","km/h":"킬로미터 매시간","m/s":"미터 매초","KRW":"원","USD":"달러","%":"퍼센트"]
                replacement=counted(n,unit:u)+(u.map{" "+(units[$0] ?? $0)} ?? "")
            }
            if let replacement, let r=Range(match.range,in:result) {
                result.replaceSubrange(r,with:replacement)
            }
        }
        return result
    }
}
