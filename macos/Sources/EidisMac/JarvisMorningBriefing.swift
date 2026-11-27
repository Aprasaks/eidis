import Foundation
import SwiftUI

enum JarvisBriefingIntent: Equatable {
    case show, hide
    static func parse(_ text: String) -> Self? {
        let compact=text.trimmingCharacters(in:.whitespacesAndNewlines)
            .replacingOccurrences(of:#"^(이디스|자비스|jarvis|eidis)[,，.!！\s]*"#,with:"",
                                  options:[.regularExpression,.caseInsensitive])
            .filter{ !$0.isWhitespace }
            .trimmingCharacters(in:CharacterSet(charactersIn:".!！"))
        if ["브리핑닫아","뉴스브리핑닫아","뉴스화면닫아","브리핑닫아줘"].contains(compact) {return .hide}
        guard !compact.contains("?"),!compact.contains("？") else {return nil}
        if ["오늘아침뉴스브리핑해줘","오늘아침브리핑해줘","아침뉴스브리핑해줘",
            "뉴스브리핑해줘","오늘뉴스브리핑해줘","오늘뉴스알려줘","아침브리핑해줘",
            "오늘의뉴스보여줘","뉴스브리핑보여줘","오늘뉴스보여줘",
            "뉴스브리핑띄워줘","뉴스브리핑띄워봐","뉴스브리핑다시보여줘",
            "오늘아침뉴스브리핑해봐","오늘아침뉴스브리핑","오늘아침브리핑"].contains(compact) {
            return .show
        }
        return nil
    }
}
struct JarvisBriefingArticle: Decodable, Identifiable {
    let category: String
    let publisher: String
    let title: String
    let url: String
    let publishedAt: String
    let excerpt: String
    let evidence: String
    var id: String {url}
}
struct JarvisBriefingFeed: Decodable, Identifiable {
    let category: String
    let name: String
    let url: String
    let state: String
    let checkedAt: String
    let eligible: Int
    var id: String {url}
}
struct JarvisBriefingResult: Decodable {
    let windowStart: String?
    let windowEnd: String?
    let collectedAt: String?
    let feeds: [JarvisBriefingFeed]?
    let articles: [JarvisBriefingArticle]?
    let scope: String?
}
struct JarvisBriefingJob: Decodable {
    let id: Int
    let state: String
    let requestedAt: String
    let updatedAt: String
    let result: JarvisBriefingResult

    var pending: Bool {["queued","running"].contains(state)}
    var articles: [JarvisBriefingArticle] {result.articles ?? []}
    var feeds: [JarvisBriefingFeed] {result.feeds ?? []}
    static let categories=["국내·종합","국제","경제","AI·기술"]

    var summary: String {
        if pending {return "DECHIVE, 뉴스 브리핑 \(id)번이 접수됐습니다. 아직 수집 완료를 확인하지 못했습니다. 다시 요청하면 이어서 확인할 수 있습니다."}
        if state=="failed" {return "DECHIVE, 현재 뉴스 수집에 실패했습니다. 확인하지 못한 뉴스를 만들어 읽지 않겠습니다."}
        let read=feeds.filter{$0.state=="read"}.count
        var lines=["DECHIVE, 최근 24시간 뉴스 브리핑입니다. 등록된 피드 \(feeds.count)개 중 \(read)개를 읽었습니다."]
        if state=="partial" {lines.append("일부 출처는 조회에 실패했습니다.")}
        for cat in Self.categories {
            let items=articles.filter{$0.category==cat}
            if let first=items.first(where:{$0.publisher=="연합뉴스"}) ?? items.first {
                lines.append("\(cat), \(first.publisher)에서 전한 제목입니다. \(first.title)")
            } else {
                let checked=feeds.filter{$0.category==cat && $0.state=="read"}
                lines.append(checked.isEmpty ? "\(cat)은 출처 조회에 실패했습니다." :
                    "\(cat)은 등록 피드에서 해당 기간의 표시할 새 자료를 찾지 못했습니다.")
            }
        }
        lines.append("자세한 출처와 발행 시간은 화면에 표시했습니다. 기사 본문의 사실성은 별도 검증이 필요합니다.")
        return lines.joined(separator:"\n")
    }
}
@MainActor
final class JarvisBriefingClient {
    private let session: URLSession
    private let port: Int
    init(port: Int = 8765) {
        self.port=port
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=4
        config.timeoutIntervalForResource=6
        session=URLSession(configuration:config)
    }
    private func request(_ path:String,submit:Bool=false) async throws -> JarvisBriefingJob {
        let url=URL(string:"http://127.0.0.1:\(port)/api/briefing"+path)!
        var req=URLRequest(url:url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if submit {
            req.httpMethod="POST"
            req.setValue("application/json",forHTTPHeaderField:"Content-Type")
            req.httpBody=Data("{}".utf8)
        }
        let (data,response)=try await session.data(for:req)
        guard (response as? HTTPURLResponse)?.statusCode==200,data.count<100_000 else {
            throw URLError(.badServerResponse)
        }
        let decoder=JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(JarvisBriefingJob.self,from:data)
    }
    func collect(onUpdate:(JarvisBriefingJob)->Void) async throws -> JarvisBriefingJob {
        var job=try await request("/submit",submit:true)
        try Task.checkCancellation()
        onUpdate(job)
        let deadline=Date().addingTimeInterval(32)
        while job.pending && Date()<deadline {
            try await Task.sleep(for:.milliseconds(650))
            job=try await request("/job?id=\(job.id)")
            try Task.checkCancellation()
            onUpdate(job)
        }
        return job
    }
    func cancelSession() {session.invalidateAndCancel()}
}

struct JarvisMorningBriefingView: View {
    let job: JarvisBriefingJob?
    let notice: String
    let close: ()->Void
    private func localTime(_ value:String?) -> String {
        guard let value,let date=ISO8601DateFormatter().date(from:value) else {return "미확인"}
        let format=DateFormatter()
        format.locale=Locale(identifier:"ko_KR")
        format.timeZone=TimeZone(identifier:"Asia/Seoul")
        format.dateFormat="M월 d일 HH:mm"
        return format.string(from:date)+" KST"
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text("MORNING BRIEFING")
                        .font(.system(size:11,weight:.semibold,design:.monospaced))
                        .foregroundStyle(.orange)
                    Text("오늘의 뉴스 · 최근 24시간")
                        .font(.system(size:24,weight:.semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button(action:close) {Image(systemName:"xmark.circle.fill").font(.system(size:20))}
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.65))
                    .accessibilityLabel("뉴스 브리핑 닫기")
            }
            Text(notice).font(.system(size:12)).foregroundStyle(.orange)
                .fixedSize(horizontal:false,vertical:true)
            if let job {
                Text("수집 \(localTime(job.result.collectedAt)) · 기간 \(localTime(job.result.windowStart)) ~ \(localTime(job.result.windowEnd))")
                    .font(.system(size:10,design:.monospaced)).foregroundStyle(.white.opacity(0.67))
                if job.pending {ProgressView().controlSize(.small).tint(.orange)}
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        ForEach(JarvisBriefingJob.categories,id:\.self) { category in
                            let items=job.articles.filter{$0.category==category}
                            let feeds=job.feeds.filter{$0.category==category}
                            VStack(alignment:.leading,spacing:9) {
                                HStack {
                                    Text(category).font(.system(size:15,weight:.semibold)).foregroundStyle(.orange)
                                    Spacer()
                                    Text("\(items.count)건").font(.system(size:11)).foregroundStyle(.white.opacity(0.55))
                                }
                                if items.isEmpty {
                                    Text(job.pending ? "수집 중" :
                                        feeds.contains(where:{$0.state=="read"}) ? "등록 피드에서 해당 기간 자료 없음" : "출처 조회 미확인 또는 실패")
                                        .font(.system(size:12)).foregroundStyle(.white.opacity(0.60))
                                }
                                ForEach(items) {item in
                                    VStack(alignment:.leading,spacing:5) {
                                        if let url=URL(string:item.url),url.scheme=="https" {
                                            Link(destination:url) {
                                                Text(item.title).font(.system(size:14,weight:.medium))
                                                    .foregroundStyle(.white).multilineTextAlignment(.leading)
                                            }
                                        } else {Text(item.title).foregroundStyle(.white)}
                                        if !item.excerpt.isEmpty && item.excerpt != item.title {
                                            Text(item.excerpt).font(.system(size:11))
                                                .foregroundStyle(.white.opacity(0.68)).lineLimit(3)
                                        }
                                        Text("\(item.publisher) · 발행처 표시 \(localTime(item.publishedAt)) · RSS 확인")
                                            .font(.system(size:10)).foregroundStyle(.white.opacity(0.52))
                                    }
                                    .frame(maxWidth:.infinity,alignment:.leading)
                                    .padding(10)
                                    .background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:8))
                                }
                            }
                        }
                        Divider()
                        Text("수집 출처 / 실제 상태")
                            .font(.system(size:12,weight:.semibold)).foregroundStyle(.orange)
                        ForEach(job.feeds) {feed in
                            HStack {
                                Text("\(feed.name) · \(feed.category)").foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text(feed.state=="read" ? "RSS 확인 · \(feed.eligible)건" : "조회 실패")
                                    .foregroundStyle(feed.state=="read" ? .green : .orange)
                            }.font(.system(size:11))
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.scrollIndicators(.visible)
            } else { Spacer() }
            Text("발행처 RSS의 최신 제목·소개문입니다. 기사 전체 열람 또는 사실 검증 완료가 아니며, 보도 중요도를 평가한 순위가 아닙니다.")
                .font(.system(size:10)).foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal:false,vertical:true)
        }
        .padding(18)
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background(Color(red:0.04,green:0.045,blue:0.055),in:RoundedRectangle(cornerRadius:16))
        .overlay(RoundedRectangle(cornerRadius:16).stroke(.orange.opacity(0.35),lineWidth:1))
        .accessibilityIdentifier("jarvis-morning-briefing")
    }
}
