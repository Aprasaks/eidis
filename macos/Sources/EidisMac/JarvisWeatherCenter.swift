import Foundation
import SwiftUI

struct WeatherTown: Equatable, Identifiable {
    let name:String; let latitude:Double; let longitude:Double
    var id:String{name}
    static let towns:[Self]=[
        .init(name:"군산",latitude:35.9675,longitude:126.7369),
        .init(name:"서울",latitude:37.5665,longitude:126.9780),
        .init(name:"고양",latitude:37.6584,longitude:126.8320),
        .init(name:"전주",latitude:35.8242,longitude:127.1480),
        .init(name:"부산",latitude:35.1796,longitude:129.0756),
        .init(name:"인천",latitude:37.4563,longitude:126.7052),
        .init(name:"대전",latitude:36.3504,longitude:127.3845),
        .init(name:"대구",latitude:35.8714,longitude:128.6014),
        .init(name:"광주",latitude:35.1595,longitude:126.8526),
        .init(name:"제주",latitude:33.4996,longitude:126.5312)
    ]
}
enum WeatherIntent:Equatable {
    case show(WeatherTown?,Bool), refresh, hide, unsupported
    static func parse(_ raw:String)->Self? {
        let s=raw.lowercased().replacingOccurrences(of:#"^(자비스|jarvis)[,，.!！\s]*"#,with:"",options:.regularExpression).filter{!$0.isWhitespace}.trimmingCharacters(in:CharacterSet(charactersIn:".!?！요"))
        if ["날씨닫아","날씨화면닫아","날씨보드닫아","웨더센터닫아","날씨화면닫아줘"].contains(s){return .hide}
        if ["날씨갱신해","날씨새로고침","날씨다시조회해줘","날씨갱신해줘"].contains(s){return .refresh}
        guard !["하지마","보여주지마","알려주지마","설명","원리","역사","만들어","코드","주식","뉴스","특보","미세먼지"].contains(where:{s.contains($0)}) else{return nil}
        var cityPrefix=s
        var timePrefix=""
        for prefix in ["오늘","내일","현재","이번주"] where s.hasPrefix(prefix) {
            let tail=String(s.dropFirst(prefix.count))
            if WeatherTown.towns.contains(where:{tail.hasPrefix($0.name)}){cityPrefix=tail;timePrefix=prefix;break}
        }
        let town=WeatherTown.towns.first{ cityPrefix.hasPrefix($0.name) }
        var rest=cityPrefix
        if let t=town{rest=String(cityPrefix.dropFirst(t.name.count));if rest.hasPrefix("시"){rest.removeFirst()}}
        rest=timePrefix+rest
        if ["날씨","오늘날씨","내일날씨","현재날씨","주간날씨","이번주날씨","시간별날씨","시간별예보","날씨예보","일기예보","웨더센터","날씨화면","날씨보드","강수확률","오늘강수확률","내일강수확률"].contains(where:{base in
            ["","어때","보여줘","알려줘","띄워줘","띄워봐","열어","열어줘","어떻게돼","어떻니","확인해줘"].contains(where:{rest==base+$0})
        }){return .show(town,rest.contains("내일"))}
        if s.contains("날씨") && ["보여줘","알려줘","어때","띄워봐"].contains(where:{s.hasSuffix($0)}) {return .unsupported}
        return nil
    }
}
struct WeatherCurrent:Decodable {
    let time:String
    let temperature_2m:Double?
    let apparent_temperature:Double?
    let relative_humidity_2m:Double?
    let precipitation:Double?
    let wind_speed_10m:Double?
    let weather_code:Int?
    let is_day:Int?
}
struct WeatherHourly:Decodable {
    let time:[String];let temperature_2m:[Double?];let precipitation_probability:[Int?];let weather_code:[Int?]
}
struct WeatherDaily:Decodable {
    let time:[String];let temperature_2m_max:[Double?];let temperature_2m_min:[Double?];let precipitation_probability_max:[Int?];let weather_code:[Int?]
}
struct WeatherPayload:Decodable {
    let timezone:String;let utc_offset_seconds:Int;let current:WeatherCurrent;let hourly:WeatherHourly;let daily:WeatherDaily
    var valid:Bool {
        timezone=="Asia/Seoul" && utc_offset_seconds==32400 && current.time.count==16 &&
        (1...240).contains(hourly.time.count) && (1...7).contains(daily.time.count) &&
        [hourly.temperature_2m.count,hourly.precipitation_probability.count,hourly.weather_code.count].allSatisfy{$0==hourly.time.count} &&
        [daily.temperature_2m_max.count,daily.temperature_2m_min.count,daily.precipitation_probability_max.count,daily.weather_code.count].allSatisfy{$0==daily.time.count}
    }
    static func kstDay(_ date:Date)->String {
        let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.calendar=Calendar(identifier:.gregorian);f.timeZone=TimeZone(identifier:"Asia/Seoul");f.dateFormat="yyyy-MM-dd";return f.string(from:date)
    }
    var nextHours:[Int]{Array(hourly.time.indices.filter{hourly.time[$0]>=current.time}.prefix(24))}
    static func description(_ code:Int?)->String {
        switch code {
        case 0:return "맑음"
        case 1:return "대체로 맑음"
        case 2:return "구름 조금"
        case 3:return "흐림"
        case 45,48:return "안개"
        case 51,53,55:return "이슬비"
        case 56,57:return "어는 이슬비"
        case 61,63,65:return "비"
        case 66,67:return "어는 비"
        case 71,73,75,77:return "눈"
        case 80,81,82:return "소나기"
        case 85,86:return "눈 소나기"
        case 95,96,99:return "뇌우"
        default:return "상태 미확인"
        }
    }
    static func icon(_ code:Int?,night:Bool=false)->String{
        switch code {
        case 0:return night ? "moon.stars.fill":"sun.max.fill"
        case 1,2:return night ? "cloud.moon.fill":"cloud.sun.fill"
        case 3:return "cloud.fill"
        case 45,48:return "cloud.fog.fill"
        case 51,53,55,56,57,61,63,65,66,67,80,81,82:return "cloud.rain.fill"
        case 71,73,75,77,85,86:return "cloud.snow.fill"
        case 95,96,99:return "cloud.bolt.rain.fill"
        default:return "questionmark.circle"
        }
    }
}
struct WeatherSnapshot {
    let town:WeatherTown;let data:WeatherPayload;let fetched:Date
}
enum WeatherFailure:Error {case invalid,http(Int)}
final class WeatherNoRedirect:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping @Sendable (URLRequest?)->Void){completionHandler(nil)}
}
final class WeatherClient {
    private let session:URLSession = {
        let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=8;c.timeoutIntervalForResource=12;c.urlCache=nil;c.httpCookieStorage=nil
        return URLSession(configuration:c,delegate:WeatherNoRedirect(),delegateQueue:nil)
    }()
    func fetch(_ town:WeatherTown) async throws -> WeatherSnapshot {
        guard WeatherTown.towns.contains(town) else{throw WeatherFailure.invalid}
        var u=URLComponents();u.scheme="https";u.host="api.open-meteo.com";u.path="/v1/forecast"
        u.queryItems=[
            .init(name:"latitude",value:String(town.latitude)),.init(name:"longitude",value:String(town.longitude)),
            .init(name:"timezone",value:"Asia/Seoul"),.init(name:"forecast_days",value:"7"),
            .init(name:"temperature_unit",value:"celsius"),.init(name:"wind_speed_unit",value:"kmh"),
            .init(name:"current",value:"temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,wind_speed_10m,weather_code,is_day"),
            .init(name:"hourly",value:"temperature_2m,precipitation_probability,weather_code"),
            .init(name:"daily",value:"temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code")
        ]
        guard let url=u.url else{throw WeatherFailure.invalid}
        let (raw,response)=try await session.data(from:url)
        guard let http=response as? HTTPURLResponse else{throw WeatherFailure.invalid}
        guard http.statusCode==200 else{throw WeatherFailure.http(http.statusCode)}
        guard raw.count<250_000 else{throw WeatherFailure.invalid}
        let data=try JSONDecoder().decode(WeatherPayload.self,from:raw)
        guard data.valid,data.daily.time.first==WeatherPayload.kstDay(Date()),data.current.time.hasPrefix(WeatherPayload.kstDay(Date())) else{throw WeatherFailure.invalid}
        return .init(town:town,data:data,fetched:Date())
    }
}
@MainActor final class JarvisWeatherCenter:ObservableObject {
    @Published private(set) var visible=false
    @Published private(set) var selected=WeatherTown.towns.first{$0.name==UserDefaults.standard.string(forKey:"jarvis.weather.defaultTown")} ?? WeatherTown.towns[0]
    @Published private(set) var snapshot:WeatherSnapshot?
    @Published private(set) var notice="날씨 조회 대기"
    @Published private(set) var busy=false
    @Published private(set) var tomorrow=false
    private let client=WeatherClient()
    private var cache:[String:WeatherSnapshot]=[:]
    private var revision=UUID()
    func hide(){visible=false;revision=UUID();busy=false}
    func setDefault(_ town:WeatherTown){guard WeatherTown.towns.contains(town) else{return};UserDefaults.standard.set(town.name,forKey:"jarvis.weather.defaultTown")}
    func handle(_ intent:WeatherIntent) async ->String {
        if intent == .hide{hide();return "주인님, 날씨 화면을 닫았습니다."}
        if intent == .unsupported{return "주인님, 현재 지원하는 지역은 군산, 서울, 고양, 전주, 부산, 인천, 대전, 대구, 광주, 제주입니다. 지역을 먼저 말씀해 주세요."}
        if case .show(let town,let next)=intent {if let town{selected=town}else{selected=WeatherTown.towns.first{$0.name==UserDefaults.standard.string(forKey:"jarvis.weather.defaultTown")} ?? WeatherTown.towns[0]};tomorrow=next}
        visible=true
        let run=UUID();revision=run;busy=true
        let town=selected
        snapshot=cache[town.name]
        if let old=snapshot,intent != .refresh,Date().timeIntervalSince(old.fetched)>=0,Date().timeIntervalSince(old.fetched)<600,old.data.daily.time.first==WeatherPayload.kstDay(Date()) {
            notice="10분 이내 조회 결과 재사용";busy=false;return summary(old)
        }
        notice="Open-Meteo 실제 예보 조회 중…"
        defer{if revision==run{busy=false}}
        do{
            let result=try await client.fetch(town)
            guard revision==run,visible,!Task.isCancelled else{return ""}
            cache[town.name]=result;snapshot=result;notice="조회 완료 · 기상 모델 기반 예보"
            return summary(result)
        }catch{
            guard revision==run,visible,!Task.isCancelled else{return ""}
            notice=snapshot==nil ? "날씨 조회 실패 · 확인된 데이터 없음":"날씨 조회 실패 · 이전 자료 유지"
            return "주인님, \(town.name) 날씨를 새로 확인하지 못했습니다. \(notice)."
        }
    }
    private func summary(_ result:WeatherSnapshot)->String {
        WeatherConversation.answer(result, tomorrow:tomorrow)
    }
}

/// Present verified weather values conversationally without a second model
/// call. Relative dates are permitted only after matching the KST calendar.
enum WeatherConversation {
    static func answer(_ result:WeatherSnapshot, tomorrow:Bool, now:Date=Date())->String {
        let d=result.data
        let town=result.town.name
        let today=WeatherPayload.kstDay(now)
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=TimeZone(identifier:"Asia/Seoul")!
        let next=calendar.date(byAdding:.day,value:1,to:now).map(WeatherPayload.kstDay)
        func temp(_ n:Double?)->String? {
            guard let n,n.isFinite else{return nil}
            return (n < 0 ? "영하 " : "")+String(format:"%.1f도",abs(n))
        }
        func sky(_ code:Int?)->String? {
            switch WeatherPayload.description(code) {
            case "상태 미확인":return nil
            case "맑음":return "맑습니다."
            case "대체로 맑음":return "대체로 맑습니다."
            case "구름 조금":return "구름이 조금 끼어 있습니다."
            case "흐림":return "흐립니다."
            case let s:return s+" 상태입니다."
            }
        }
        if tomorrow {
            guard d.valid,d.daily.time.count>1,d.daily.time.first==today,d.daily.time[1]==next else {
                return "주인님, "+town+"의 내일 예보 날짜를 확인하지 못했습니다."
            }
            var sentences=["주인님, 내일 "+town+" 날씨 예보입니다."]
            switch WeatherPayload.description(d.daily.weather_code[1]) {
            case "맑음": sentences.append("맑을 것으로 예상됩니다.")
            case "대체로 맑음": sentences.append("대체로 맑을 것으로 예상됩니다.")
            case "구름 조금": sentences.append("구름이 조금 낄 것으로 예상됩니다.")
            case "흐림": sentences.append("흐릴 것으로 예상됩니다.")
            case "상태 미확인": break
            case let condition: sentences.append(condition+" 예보가 있습니다.")
            }
            let low=temp(d.daily.temperature_2m_min[1]), high=temp(d.daily.temperature_2m_max[1])
            if let low,let high {sentences.append("최저 "+low+", 최고 "+high+"로 예상됩니다.")}
            else if let low {sentences.append("최저 기온은 "+low+"로 예상됩니다.")}
            else if let high {sentences.append("최고 기온은 "+high+"로 예상됩니다.")}
            if let rain=d.daily.precipitation_probability_max[1],(0...100).contains(rain) {
                sentences.append("하루 중 최대 강수확률은 "+String(rain)+"%입니다.")
            }
            if sentences.count==1 {sentences.append("확인된 예보 수치가 없습니다.")}
            return sentences.joined(separator:" ")
        }
        guard d.daily.time.first==today,d.current.time.hasPrefix(today+"T") else {
            return "주인님, "+town+"의 오늘 날씨를 확인하지 못했습니다. 화면에 자료의 기준 시각을 표시했습니다."
        }
        var sentences:[String]=[]
        if let condition=sky(d.current.weather_code) {
            sentences.append("주인님, 지금 "+town+" 지역은 "+condition)
        } else {
            sentences.append("주인님, 지금 "+town+"의 날씨 정보입니다.")
        }
        let actual=temp(d.current.temperature_2m), feels=temp(d.current.apparent_temperature)
        if let actual,let feels {sentences.append("기온은 "+actual+", 체감온도는 "+feels+"입니다.")}
        else if let actual {sentences.append("기온은 "+actual+"입니다.")}
        else if let feels {sentences.append("체감온도는 "+feels+"입니다.")}
        else {sentences.append("기온과 체감온도는 확인되지 않았습니다.")}
        sentences.append("기상 모델 기준입니다.")
        return sentences.joined(separator:" ")
    }
}

struct JarvisWeatherCenterView:View {
    @ObservedObject var model:JarvisWeatherCenter
    private func run(_ intent:WeatherIntent){Task{_ = await model.handle(intent)}}
    private func value(_ n:Double?,_ unit:String)->String{n.map{String(format:"%.1f",$0)+unit} ?? "—"}
    private func probability(_ n:Int?)->String{n.map{String($0)+"%"} ?? "—"}
    private func metric(_ title:String,_ text:String)->some View{
        VStack(alignment:.leading,spacing:5){Text(title).font(.caption).foregroundStyle(.white.opacity(0.6));Text(text).font(.system(size:18,weight:.medium,design:.monospaced))}.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:9))
    }
    private func current(_ d:WeatherPayload)->some View {
        VStack(alignment:.leading,spacing:12){
            HStack(spacing:18){
                Image(systemName:WeatherPayload.icon(d.current.weather_code,night:d.current.is_day==0)).font(.system(size:45)).foregroundStyle(.orange)
                VStack(alignment:.leading){Text(value(d.current.temperature_2m,"°C")).font(.system(size:42,weight:.light,design:.monospaced));Text(WeatherPayload.description(d.current.weather_code)).font(.title3)}
                Spacer()
            }
            Text("기준 "+d.current.time.replacingOccurrences(of:"T",with:" ")+" KST · 모델 추정값").font(.caption)
            HStack{metric("체감",value(d.current.apparent_temperature,"°C"));metric("습도",value(d.current.relative_humidity_2m,"%"));metric("바람",value(d.current.wind_speed_10m," km/h"))}
        }.padding(14).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
    }
    private func hourly(_ d:WeatherPayload)->some View {
        VStack(alignment:.leading,spacing:8){
            Text("앞으로 24시간").font(.headline)
            ScrollView(.horizontal){
                HStack(spacing:8){ForEach(d.nextHours,id:\.self){i in
                    VStack(spacing:6){
                        Text(String(d.hourly.time[i].suffix(5))).font(.caption)
                        Text(String(d.hourly.time[i].prefix(10).suffix(5))).font(.caption2).foregroundStyle(.white.opacity(0.55))
                        Image(systemName:WeatherPayload.icon(d.hourly.weather_code[i])).foregroundStyle(.orange)
                        Text(value(d.hourly.temperature_2m[i],"°")).font(.callout.monospacedDigit())
                        Text(probability(d.hourly.precipitation_probability[i])).font(.caption2).foregroundStyle(.cyan)
                    }.frame(width:68).padding(.vertical,8).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:8))
                }}
            }
            Text("파란색: 해당 시간 강수확률").font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
    }
    private func daily(_ d:WeatherPayload)->some View {
        VStack(alignment:.leading,spacing:6){
            Text("7일 예보").font(.headline)
            ForEach(d.daily.time.indices,id:\.self){i in
                HStack{
                    Text(d.daily.time[i]).font(.caption.monospacedDigit()).frame(width:98,alignment:.leading)
                    Image(systemName:WeatherPayload.icon(d.daily.weather_code[i])).foregroundStyle(.orange).frame(width:24)
                    Text(WeatherPayload.description(d.daily.weather_code[i])).font(.caption)
                    Spacer()
                    Text(value(d.daily.temperature_2m_min[i],"°")+" / "+value(d.daily.temperature_2m_max[i],"°")).font(.caption.monospacedDigit())
                    Text(probability(d.daily.precipitation_probability_max[i])).font(.caption.monospacedDigit()).foregroundStyle(.cyan).frame(width:45,alignment:.trailing)
                }.padding(8).background(model.tomorrow && i==1 ? .orange.opacity(0.15):.white.opacity(0.04),in:RoundedRectangle(cornerRadius:6))
            }
            Text("일별 최저/최고 기온 · 최대 강수확률").font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
    }
    var body:some View{
        VStack(alignment:.leading,spacing:12){
            HStack{
                VStack(alignment:.leading){Text("WEATHER CENTER / OPEN-METEO").font(.system(size:11,weight:.semibold,design:.monospaced)).foregroundStyle(.orange);Text(model.selected.name+" 날씨").font(.system(size:25,weight:.semibold))}
                Spacer()
                Button("새로고침"){run(.refresh)}.disabled(model.busy)
                Button{model.hide()}label:{Image(systemName:"xmark.circle.fill").font(.title2)}.buttonStyle(.plain)
            }
            HStack{
                Picker("지역",selection:Binding(get:{model.selected.name},set:{name in if let town=WeatherTown.towns.first(where:{$0.name==name}){run(.show(town,false))}})){
                    ForEach(WeatherTown.towns){Text($0.name).tag($0.name)}
                }
                Button("기본 지역으로 저장"){model.setDefault(model.selected)}
                if model.busy{ProgressView().controlSize(.small)}
            }
            Text(model.notice).font(.caption).foregroundStyle(.orange)
            ScrollView{
                VStack(alignment:.leading,spacing:14){
                    if let s=model.snapshot{
                        current(s.data);hourly(s.data);daily(s.data)
                        Text("조회: "+s.fetched.formatted(date:.abbreviated,time:.shortened)).font(.caption2)
                    }else{Text("확인된 날씨 자료 없음").foregroundStyle(.white.opacity(0.6)).padding(28)}
                }
            }
            Link("출처: Open-Meteo · CC BY 4.0 · 모델 예보 / 특보 아님",destination:URL(string:"https://open-meteo.com/")!).font(.caption2)
        }.padding(20).foregroundStyle(.white).background(.black.opacity(0.78),in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).strokeBorder(.orange.opacity(0.35)))
        .accessibilityIdentifier("jarvis-weather-center")
    }
}

