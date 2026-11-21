import Foundation
import SwiftUI
import Security
import Charts

enum StockBoardIntent: Equatable {
    case show(String), ranking(String, String, Int), symbols([String]), watchlist, addWatch([String]), removeWatch([String]), chart(String,String), refresh, hide
    static let domestic = ["005930","000660","005380","035420","035720"]
    static let american = ["NVDA","AAPL","MSFT","TSLA","AMZN"]
    static let aliases = ["삼성전자":"005930","SK하이닉스":"000660","하이닉스":"000660","현대차":"005380","네이버":"035420","카카오":"035720","엔비디아":"NVDA","애플":"AAPL","마이크로소프트":"MSFT","테슬라":"TSLA","아마존":"AMZN"]
    static func parse(_ raw: String) -> Self? {
        let s = raw.uppercased().replacingOccurrences(of: #"^(자비스|JARVIS)[,\s.!]*"#, with:"",options:.regularExpression).filter{ !$0.isWhitespace }.trimmingCharacters(in:CharacterSet(charactersIn:".!！"))
        guard !["하지마","말고","않아","안해","안띄워","매수","매도","주문","팔아","사줘","사라","구매","취소","보유","계좌","예상","추천"].contains(where:{s.contains($0)}) else {return nil}
        if ["주식현황표닫아","주식화면닫아","주식보드닫아","주식현황닫아"].contains(s) {return .hide}
        if ["주식현황갱신해","주식현황새로고침","주식보드갱신해","주식현황표갱신해","주식현황갱신해줘","주식현황새로고침해줘"].contains(s) {return .refresh}
        if ["관심종목보여줘","관심종목띄워봐","관심종목띄워줘","관심종목열어"].contains(s) {return .watchlist}
        let codes = aliases.keys.sorted{ $0.count > $1.count }.filter{ s.contains($0) }.compactMap{aliases[$0]}
        let unique = codes.reduce(into:[String]()){if !$0.contains($1){$0.append($1)}}
        if s.contains("관심종목"),!unique.isEmpty {
            if ["추가해","추가해줘","등록해","등록해줘"].contains(where:{s.hasSuffix($0)}) {return .addWatch(unique)}
            if ["삭제해","삭제해줘","빼줘","제거해"].contains(where:{s.hasSuffix($0)}) {return .removeWatch(unique)}
        }
        let request = ["보여줘","띄워봐","띄워줘","알려줘","비교해봐","비교해줘","열어","열어줘","어때?","어때","바꿔봐","바꿔줘"].contains{ s.hasSuffix($0) }
        guard request else {return nil}
        let market = ["미국","해외"].contains{ s.contains($0) } ? "US":"KR"
        let type = s.contains("거래량") ? "MARKET_TRADING_VOLUME" : s.contains("거래대금") ? "MARKET_TRADING_AMOUNT" : s.contains("급상승") || s.contains("상승률") ? "TOP_GAINERS" : s.contains("하락률") || s.contains("급하락") ? "TOP_LOSERS" : nil
        if let type, ["종목","상위","순위","주식"].contains(where:{s.contains($0)}) {
            let n = s.range(of:#"\d{1,3}개"#,options:.regularExpression).flatMap{Int(s[$0].dropLast())} ?? 20
            return .ranking(market,type,min(100,max(1,n)))
        }
        if unique.count == 1, s.contains("차트") || s.contains("분봉") || s.contains("일봉") {
            if s.contains("분봉"),!s.contains("1분봉"){return nil}
            return .chart(unique[0],s.contains("1분봉") ? "1m":"1d")
        }
        if !unique.isEmpty && ["주가","현재가","시세","주식","비교","보여","띄워"].contains(where:{s.contains($0)}) {return .symbols(unique)}
        if ["주식현황","주식보드","주식대시보드","국내증시","미국증시","미국주식","국내주식"].contains(where:{s.contains($0)}) {return .show(market)}
        return nil
    }
}
struct StockQuote: Codable, Identifiable {
    let symbol: String; let timestamp: String; let lastPrice: String; let currency: String
    var id: String {symbol}
}
struct StockMaster: Decodable {let symbol: String; let name: String; let currency: String?}
struct StockIndex: Decodable, Identifiable {let symbol: String; let timestamp: String; let lastPrice: String; var id:String{symbol}}
struct StockRankingPrice: Decodable {let lastPrice: String; let changeRate: String?}
struct StockRank: Decodable {let rank: Int; let symbol: String; let currency: String; let price: StockRankingPrice; let tradingVolume: String?}
struct StockRanks: Decodable {let rankedAt: String?; let rankings: [StockRank]}
struct StockEnvelope<T: Decodable>: Decodable {let result: T}
struct StockCandle: Decodable, Identifiable {
    let timestamp: String; let closePrice: String; let volume: String; let currency: String
    var id: String {timestamp}
    var date: Date? {StockMarketDay.parse(timestamp)}
    var close: Double? {Double(closePrice).flatMap{$0.isFinite ? $0 : nil}}
}
struct StockCandlePage: Decodable {let candles:[StockCandle]}
struct StockSession: Decodable {
    let startTime:String; let endTime:String
    func contains(_ date:Date)->Bool {
        guard let start=StockMarketDay.parse(startTime),let end=StockMarketDay.parse(endTime) else{return false}
        return start <= date && date < end
    }
}
struct StockMarketDay: Decodable {
    let date:String
    let integrated:StockMarketSessions?
    let dayMarket:StockSession?
    let preMarket:StockSession?
    let regularMarket:StockSession?
    let afterMarket:StockSession?
    static func parse(_ text:String)->Date? {
        let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return f.date(from:text) ?? ISO8601DateFormatter().date(from:text)
    }
    var sessions:[(String,StockSession)] {
        let list:[(String,StockSession?)]=[("데이마켓",dayMarket),("프리마켓",integrated?.preMarket ?? preMarket),("정규장",integrated?.regularMarket ?? regularMarket),("애프터마켓",integrated?.afterMarket ?? afterMarket)]
        return list.compactMap{label,session in session.map{(label,$0)}}
    }
}
struct StockMarketSessions:Decodable {let preMarket:StockSession?;let regularMarket:StockSession?;let afterMarket:StockSession?}
struct StockMarketCalendar:Decodable {
    let today:StockMarketDay
    let previousBusinessDay:StockMarketDay?
    let nextBusinessDay:StockMarketDay?
    static func dayKey(_ now:Date,market:String)->String {
        let f=DateFormatter();f.calendar=Calendar(identifier:.gregorian);f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(identifier:market=="US" ? "America/New_York":"Asia/Seoul");f.dateFormat="yyyy-MM-dd";return f.string(from:now)
    }
    func status(_ now:Date,market:String)->String {
        guard today.date==Self.dayKey(now,market:market) else{return "달력 날짜 갱신 필요"}
        for day in [today,previousBusinessDay,nextBusinessDay].compactMap({$0}) {
            if let active=day.sessions.first(where:{$0.1.contains(now)}){return active.0+" 예정 시간대"}
        }
        if today.sessions.isEmpty{return "휴장일 · 공식 달력"}
        return "거래 예정 시간 외"
    }
}
struct StockToken: Decodable {let access_token: String; let expires_in: Int}
struct StockCredentials: Codable {let id: String; let secret: String}
enum StockError: LocalizedError {
    case setup, invalid, http(Int), storage
    var errorDescription:String? {
        switch self {
        case .setup: return "토스증권 전용 API 키를 등록하세요."
        case .invalid: return "응답 또는 종목 코드 형식이 올바르지 않습니다."
        case .storage: return "Mac 키체인 저장에 실패했습니다."
        case .http(let code):
            switch code {
            case 401:return "인증 실패 또는 토큰 만료 · 다른 앱과 키 공유 여부 확인"
            case 403:return "접근 거부 · 토스증권 허용 IP와 권한 확인"
            case 429:return "호출 한도 초과 · 자동 갱신 중지"
            default:return "토스증권 조회 실패 (HTTP \(code))"
            }
        }
    }
}
enum StockKeychain {
    static var query:[String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"dev.dechive.jarvis.toss.readonly",kSecAttrAccount as String:"credentials"] }
    static func load() -> StockCredentials? {
        var q = query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess,let data=result as? Data else{return nil}
        return try? JSONDecoder().decode(StockCredentials.self,from:data)
    }
    static func save(_ credentials:StockCredentials) throws {
        let data=try JSONEncoder().encode(credentials)
        let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status==errSecItemNotFound {
            var q=query; q[kSecValueData as String]=data
            guard SecItemAdd(q as CFDictionary,nil)==errSecSuccess else {throw StockError.storage}
        } else if status != errSecSuccess {throw StockError.storage}
    }
}
final class StockNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session:URLSession, task:URLSessionTask, willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping @Sendable (URLRequest?)->Void){completionHandler(nil)}
}
@MainActor final class JarvisStockBoard: ObservableObject {
    @Published private(set) var visible=false
    @Published private(set) var quotes:[StockQuote]=[]
    @Published private(set) var indices:[StockIndex]=[]
    @Published private(set) var names:[String:String]=[:]
    @Published private(set) var ranks:[StockRank]=[]
    @Published private(set) var rankedAt:String?
    @Published private(set) var notice="토스증권 연결 대기"
    @Published private(set) var busy=false
    @Published var autoRefresh=false
    @Published private(set) var mode:StockBoardIntent = .show("KR")
    @Published private(set) var checked:Date?
    @Published private(set) var watchlist:[String] = UserDefaults.standard.stringArray(forKey:"jarvis.stock.watchlist") ?? []
    @Published private(set) var candles:[StockCandle]=[]
    @Published private(set) var calendars:[String:StockMarketCalendar]=[:]
    func updateWatch(_ codes:[String],remove:Bool=false)->Bool {
        guard let valid=Self.cleanSymbols(codes.joined(separator:",")),!busy else{return false}
        var list=watchlist
        for code in valid {
            if remove{list.removeAll{$0==code}}
            else if !list.contains(code){list.append(code)}
        }
        guard list.count<=30 else{return false}
        watchlist=list;UserDefaults.standard.set(list,forKey:"jarvis.stock.watchlist");return true
    }
    private var token:String?
    private var expires=Date.distantPast
    private var revision=UUID()
    private let session:URLSession={
        let c=URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest=8; c.timeoutIntervalForResource=12
        c.httpCookieStorage=nil; c.urlCache=nil
        return URLSession(configuration:c,delegate:StockNoRedirect(),delegateQueue:nil)
    }()
    func hide(){visible=false;autoRefresh=false;revision=UUID()}
    static func cleanSymbols(_ s:String)->[String]? {
        let a=s.uppercased().split(whereSeparator:{$0=="," || $0.isWhitespace}).map(String.init)
        guard !a.isEmpty,a.count<=30,a.allSatisfy({$0.range(of:#"^[A-Z0-9][A-Z0-9.-]{0,19}$"#,options:.regularExpression) != nil}) else{return nil}
        return a.reduce(into:[String]()){if !$0.contains($1){$0.append($1)}}
    }
    func save(id:String,secret:String) throws {
        guard !id.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,!secret.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,Bool(!busy) else{throw StockError.invalid}
        try StockKeychain.save(.init(id:id.trimmingCharacters(in:.whitespacesAndNewlines),secret:secret.trimmingCharacters(in:.whitespacesAndNewlines)))
        token=nil; expires = .distantPast; notice="키 저장 완료 · 실제 조회로 확인하세요."
    }
    private func request<T:Decodable>(_ path:String,_ query:[URLQueryItem]=[],body:Data?=nil,bearer:String?=nil) async throws -> T {
        let allowed=["/oauth2/token","/api/v1/prices","/api/v1/stocks","/api/v1/rankings","/api/v1/market-indicators/prices","/api/v1/candles","/api/v1/market-calendar/KR","/api/v1/market-calendar/US"]
        guard allowed.contains(path), (path == "/oauth2/token") == (body != nil) else{throw StockError.invalid}
        var c=URLComponents();c.scheme="https";c.host="openapi.tossinvest.com";c.path=path
        if !query.isEmpty{c.queryItems=query}
        guard let url=c.url else{throw StockError.invalid}
        var req=URLRequest(url:url)
        if let body{req.httpMethod="POST";req.httpBody=body;req.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")}
        if let bearer{req.setValue("Bearer "+bearer,forHTTPHeaderField:"Authorization")}
        let (data,response)=try await session.data(for:req)
        guard let http=response as? HTTPURLResponse else{throw StockError.invalid}
        guard http.statusCode==200 else{throw StockError.http(http.statusCode)}
        guard data.count<2_000_000 else{throw StockError.invalid}
        return try JSONDecoder().decode(T.self,from:data)
    }
    private func auth() async throws -> String {
        if let token,expires>Date().addingTimeInterval(60){return token}
        guard let c=StockKeychain.load() else{throw StockError.setup}
        let allowed=CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-._~"))
        func enc(_ s:String)->String{s.addingPercentEncoding(withAllowedCharacters:allowed) ?? ""}
        let body=Data("grant_type=client_credentials&client_id=\(enc(c.id))&client_secret=\(enc(c.secret))".utf8)
        let r:StockToken=try await request("/oauth2/token",body:body)
        guard !r.access_token.isEmpty,r.expires_in>0 else{throw StockError.invalid}
        token=r.access_token;expires=Date().addingTimeInterval(Double(r.expires_in));return r.access_token
    }
    func open(_ intent:StockBoardIntent) async -> String {
        if intent == .hide{hide();return "주인님, 주식 현황표를 닫았습니다."}
        if busy{return "주인님, 주식 시세 조회가 진행 중입니다."}
        visible=true
        switch intent {
        case .addWatch(let codes), .removeWatch(let codes):
            let remove:Bool
            if case .removeWatch = intent {remove=true}else{remove=false}
            guard updateWatch(codes,remove:remove) else{return "관심 종목을 변경하지 못했습니다. 최대 30종목입니다."}
            autoRefresh=false;mode = .watchlist;quotes=[];ranks=[];rankedAt=nil;candles=[];indices=[];calendars=[:];names=[:];checked=nil
            let result=await refresh()
            return "관심 종목 목록을 저장했습니다. "+result
        default:break
        }
        if intent != .refresh {
            mode=intent;quotes=[];ranks=[];rankedAt=nil;names=[:];checked=nil;candles=[];calendars=[:];indices=[]
        }
        return await refresh()
    }
    func refresh() async -> String {
        guard visible,!busy else{return "주식 조회 대기 중입니다."}
        if mode == .watchlist && watchlist.isEmpty {
            autoRefresh=false;quotes=[];notice="관심 종목 없음 · 종목 코드를 추가하세요.";return notice
        }
        busy=true;let run=UUID();revision=run;notice="토스증권 조회 중…"
        defer{busy=false}
        do {
            let t=try await auth()
            try Task.checkCancellation()
            guard revision==run,visible else{return "주식 조회가 취소되었습니다."}
            var q:[StockQuote]=[];var r:[StockRank]=[];var rt:String?
            let codes:[String]
            switch mode {
            case .show(let market): codes=market=="US" ? StockBoardIntent.american:StockBoardIntent.domestic
            case .symbols(let s):codes=s
            case .watchlist:codes=watchlist
            case .chart(let symbol,_):codes=[symbol]
            case .ranking(let market,let type,let count):
                let result:StockEnvelope<StockRanks>=try await request("/api/v1/rankings",[.init(name:"marketCountry",value:market),.init(name:"type",value:type),.init(name:"duration",value:"1d"),.init(name:"count",value:String(count))],bearer:t)
                r=result.result.rankings;rt=result.result.rankedAt;codes=r.map(\.symbol)
            default:throw StockError.invalid
            }
            let symbols=[URLQueryItem(name:"symbols",value:codes.joined(separator:","))]
            if r.isEmpty && !codes.isEmpty {
                let result:StockEnvelope<[StockQuote]>=try await request("/api/v1/prices",symbols,bearer:t)
                q=result.result.filter{codes.contains($0.symbol)}
            }
            var localNames:[String:String]=[:];var currencies:[String:String]=[:];var warnings:[String]=[]
            guard revision==run,visible,!Task.isCancelled else{return "주식 조회가 취소되었습니다."}
            if !codes.isEmpty{
                do{let m:StockEnvelope<[StockMaster]>=try await request("/api/v1/stocks",symbols,bearer:t);for item in m.result{localNames[item.symbol]=item.name;currencies[item.symbol]=item.currency}}
                catch{warnings.append("종목명 조회 실패")}
            }
            guard revision==run,visible,!Task.isCancelled else{return "주식 조회가 취소되었습니다."}
            var idx:[StockIndex]=[]
            do{let response:StockEnvelope<[StockIndex]>=try await request("/api/v1/market-indicators/prices",[.init(name:"symbols",value:"KOSPI,KOSDAQ")],bearer:t);idx=response.result}
            catch{warnings.append("국내 지수 조회 실패")}
            guard revision==run,visible,!Task.isCancelled else{return "주식 조회가 취소되었습니다."}
            for item in q {currencies[item.symbol]=item.currency}
            for item in r {currencies[item.symbol]=item.currency}
            var marketCodes=Set(codes.compactMap{symbol in
                currencies[symbol]=="KRW" ? "KR" : currencies[symbol]=="USD" ? "US" : nil
            })
            if marketCodes.isEmpty && !codes.isEmpty {warnings.append("종목 시장 미확인")}
            if case .show(let market)=mode{marketCodes=[market]}
            if case .ranking(let market,_,_)=mode{marketCodes=[market]}
            var localCalendars:[String:StockMarketCalendar]=[:]
            for market in marketCodes.sorted() {
                guard revision==run,visible,!Task.isCancelled else{return "주식 조회가 취소되었습니다."}
                do {
                    let calendar:StockEnvelope<StockMarketCalendar>=try await request("/api/v1/market-calendar/"+market,[.init(name:"date",value:StockMarketCalendar.dayKey(Date(),market:market))],bearer:t)
                    localCalendars[market]=calendar.result
                } catch{warnings.append(market+" 운영 달력 조회 실패")}
            }
            var localCandles:[StockCandle]=[]
            if case .chart(let symbol,let interval)=mode {
                guard revision==run,visible,!Task.isCancelled else{return "주식 조회가 취소되었습니다."}
                do {
                    let page:StockEnvelope<StockCandlePage>=try await request("/api/v1/candles",[.init(name:"symbol",value:symbol),.init(name:"interval",value:interval),.init(name:"count",value:"60")],bearer:t)
                    localCandles=page.result.candles.filter{$0.date != nil && $0.close != nil}.sorted{($0.date ?? .distantPast)<($1.date ?? .distantPast)}
                    if localCandles.isEmpty{warnings.append("차트 자료 없음")}
                }catch{warnings.append("차트 조회 실패")}
            }
            guard revision==run,visible,!Task.isCancelled else{return "주식 조회가 취소되었습니다."}
            quotes=q;ranks=r;rankedAt=rt;names=localNames;indices=idx;checked=Date();calendars=localCalendars;candles=localCandles
            if q.count+r.count==0{warnings.append("표시할 시세 없음")}
            if !r.isEmpty,rt==nil{warnings.append("랭킹 집계 시각 미확인")}
            if r.isEmpty,!codes.isEmpty,q.count != codes.count{warnings.append("일부 종목 시세 누락")}
            if !warnings.isEmpty{autoRefresh=false}
            notice=warnings.isEmpty ? "토스증권 조회 완료 · 실시간 스트리밍 아님" : warnings.joined(separator:" · ")
            if case .symbols(let requested)=mode,requested.count<=3,!q.isEmpty {
                let brief=q.map{"\(localNames[$0.symbol] ?? $0.symbol) \($0.lastPrice) \($0.currency)"}.joined(separator:", ")
                return "주인님, 토스증권 조회 결과입니다. \(brief). 시세 기준 시각은 화면에서 확인하세요."
            }
            return "주인님, 토스증권 시세 \(q.count+r.count)개를 화면에 표시했습니다. \(notice)."
        } catch {
            guard revision==run else{return "주식 조회가 취소되었습니다."}
            autoRefresh=false
            if case StockError.http(401)=error{token=nil;expires = .distantPast}
            notice=(error as? StockError)?.localizedDescription ?? "네트워크 또는 응답 확인 실패"
            if checked != nil{notice += " · 이전 조회 값 유지"}
            return "주인님, \(notice). 확인하지 않은 시세는 표시하지 않겠습니다."
        }
    }
}
struct JarvisStockBoardView:View {
    @ObservedObject var model:JarvisStockBoard
    @State private var id=""
    @State private var secret=""
    @State private var settings=false
    @State private var codes=""
    @State private var validation=""
    private func run(_ intent:StockBoardIntent){Task{_ = await model.open(intent)}}
    private func format(_ value:String)->String {
        let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        guard let date=f.date(from:value) ?? ISO8601DateFormatter().date(from:value) else{return value}
        let d=DateFormatter();d.timeZone=TimeZone(identifier:"Asia/Seoul");d.dateFormat="MM-dd HH:mm:ss";return d.string(from:date)+" KST"
    }
    private func row(_ name:String,_ symbol:String,_ price:String,_ currency:String,_ time:String,_ rate:String?=nil,_ volume:String?=nil)->some View {
        HStack(spacing:10){
            VStack(alignment:.leading){Text(name).font(.system(size:15,weight:.medium));Text(symbol).font(.caption).foregroundStyle(.white.opacity(0.55))}
            Spacer()
            VStack(alignment:.trailing){
                Text(price+" "+currency).font(.system(size:18,weight:.semibold,design:.monospaced))
                Text(time).font(.system(size:10)).foregroundStyle(.white.opacity(0.65))
                if let rate,let n=Double(rate),n.isFinite{Text(String(format:"%+.2f%%",n*100)).foregroundStyle(n>=0 ? .red:.cyan)}
                if let volume{Text("거래량 "+volume).font(.caption)}
            }
        }.padding(10).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
    }
    @ViewBuilder private var watchControls:some View {
            HStack {
                Button("관심 추가"){if let s=JarvisStockBoard.cleanSymbols(codes){run(.addWatch(s))}else{validation="종목 코드를 입력하세요."}}
                Button("관심 삭제"){if let s=JarvisStockBoard.cleanSymbols(codes){run(.removeWatch(s))}else{validation="종목 코드를 입력하세요."}}
                Button("일봉"){if let s=JarvisStockBoard.cleanSymbols(codes),s.count==1{run(.chart(s[0],"1d"))}else{validation="종목 코드 한 개를 입력하세요."}}
                Button("1분봉"){if let s=JarvisStockBoard.cleanSymbols(codes),s.count==1{run(.chart(s[0],"1m"))}else{validation="종목 코드 한 개를 입력하세요."}}
                Spacer()
                Text("관심 \(model.watchlist.count) / 30").font(.caption)
            }.disabled(model.busy)
            if !model.watchlist.isEmpty {Text(model.watchlist.joined(separator:", ")).font(.caption2).lineLimit(2)}
    }
    private var marketCalendarView:some View {
            TimelineView(.periodic(from:.now,by:30)){context in
                VStack(alignment:.leading){
                    Text("시세 기준 시각 · KST / 운영 상태는 공식 달력 시간대 기준")
                    if model.calendars.isEmpty{Text("장 운영 상태 미확인")}
                    ForEach(model.calendars.keys.sorted(),id:\.self){market in
                        if let cal=model.calendars[market] {
                            let state=cal.status(context.date,market:market)
                            let next=cal.nextBusinessDay?.date ?? "미확인"
                            Text("\(market) · \(state) · 다음 영업일 \(next)")
                        }
                    }
                }.font(.caption2)
            }
    }
    @ViewBuilder private var stockChartView:some View {
                    if case .chart(let symbol,let interval)=model.mode {
                        Text((model.names[symbol] ?? symbol)+" · "+(interval=="1m" ? "1분봉":"일봉")+" 종가선 · 최근 최대 60개").font(.caption)
                        if !model.candles.isEmpty {
                            Chart(model.candles){c in
                                if let date=c.date,let close=c.close {
                                    LineMark(x:.value("시각",date),y:.value("종가",close)).foregroundStyle(.orange)
                                    PointMark(x:.value("시각",date),y:.value("종가",close)).foregroundStyle(.orange).symbolSize(8)
                                }
                            }.chartYScale(domain:.automatic(includesZero:false)).frame(height:180)
                            if let last=model.candles.last {Text("마지막 봉 "+format(last.timestamp)+" · 거래량 "+last.volume+" · "+last.currency).font(.caption2)}
                        }else{Text("확인된 차트 없음").font(.caption)}
                    }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{
                VStack(alignment:.leading){Text("STOCK BOARD / TOSS").font(.system(size:11,weight:.semibold,design:.monospaced)).foregroundStyle(.orange);Text("주식 시장 관제").font(.system(size:25,weight:.semibold))}
                Spacer()
                Button("API 설정"){id="";secret="";validation="";settings=true}
                Button{model.hide()}label:{Image(systemName:"xmark.circle.fill").font(.title2)}.buttonStyle(.plain)
            }
            Text(model.notice).font(.caption).foregroundStyle(.orange)
            HStack{
                Button("국내"){run(.show("KR"))};Button("미국"){run(.show("US"))}
                Button("관심"){run(.watchlist)}
                Button("거래량 상위"){run(.ranking("KR","MARKET_TRADING_VOLUME",20))}
                Button("갱신"){run(.refresh)}
                Toggle("60초 자동",isOn:$model.autoRefresh).toggleStyle(.switch).controlSize(.small).disabled(model.checked==nil)
                if model.busy{ProgressView().controlSize(.small)}
            }.disabled(model.busy)
            HStack{
                TextField("종목 코드: 005930, NVDA",text:$codes)
                Button("종목 조회"){if let s=JarvisStockBoard.cleanSymbols(codes){validation="";run(.symbols(s))}else{validation="종목 코드 1~30개를 입력하세요."}}.disabled(model.busy)
            }
            watchControls
            if !validation.isEmpty{Text(validation).font(.caption).foregroundStyle(.orange)}
            if !model.indices.isEmpty {
                HStack{ForEach(model.indices){i in VStack(alignment:.leading){Text(i.symbol).font(.caption).foregroundStyle(.orange);Text(i.lastPrice).font(.title2.monospacedDigit());Text(format(i.timestamp)).font(.caption2)}.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:8))}}
            }
            marketCalendarView
            Text("실제 거래소 운영 여부와 시세 지연은 별도 확인").font(.caption2).foregroundStyle(.white.opacity(0.65))
            if case .ranking(_,let type,_)=model.mode{Text("시장 순위 · 1일 · "+type).font(.caption)}
            ScrollView{
                LazyVStack(spacing:6){
                    stockChartView
                    ForEach(model.quotes){q in row(model.names[q.symbol] ?? q.symbol,q.symbol,q.lastPrice,q.currency,format(q.timestamp))}
                    ForEach(model.ranks,id:\.symbol){r in row("\(r.rank). "+(model.names[r.symbol] ?? r.symbol),r.symbol,r.price.lastPrice,r.currency,model.rankedAt.map(format) ?? "집계 시각 미확인",r.price.changeRate,r.tradingVolume)}
                    if model.quotes.isEmpty && model.ranks.isEmpty{Text("확인된 시세 없음").foregroundStyle(.white.opacity(0.55)).padding(28)}
                }
            }
            Text("출처: 토스증권 Open API · 조회 전용 · 주문 기능 없음").font(.caption2).foregroundStyle(.white.opacity(0.60))
        }.padding(20).foregroundStyle(.white).background(.black.opacity(0.78),in:RoundedRectangle(cornerRadius:20))
        .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(.orange.opacity(0.35)))
        .task(id:model.autoRefresh){
            guard model.autoRefresh else{return}
            while !Task.isCancelled && model.visible && model.autoRefresh{
                do{try await Task.sleep(for:.seconds(60))}catch{return}
                guard !Task.isCancelled,model.visible,model.autoRefresh else{return}
                _ = await model.refresh()
            }
        }
        .sheet(isPresented:$settings){
            VStack(alignment:.leading,spacing:14){
                Text("토스증권 API 연결").font(.title2)
                Text("자비스 전용 키를 사용하세요. 새 토큰은 같은 클라이언트의 기존 토큰을 무효화합니다. 토스증권 허용 IP 등록이 필요합니다.").font(.callout)
                TextField("Client ID",text:$id);SecureField("Client Secret",text:$secret)
                Link("토스증권 공식 API 안내",destination:URL(string:"https://developers.tossinvest.com/docs")!)
                Text(validation).foregroundStyle(.orange)
                HStack{Button("취소"){secret="";settings=false};Spacer();Button("키체인 저장 및 조회"){do{try model.save(id:id,secret:secret);id="";secret="";validation="";settings=false;run(.refresh)}catch{validation="키 저장 실패 · 입력값 확인"}}.disabled(model.busy)}
            }.padding(24).frame(width:470)
        }
        .accessibilityIdentifier("jarvis-stock-board")
    }
}

