import Foundation
@main struct WeatherTests {
    static func main() async throws {
        let gunsan=WeatherTown.towns[0]
        let seoul=WeatherTown.towns[1]
        precondition(WeatherIntent.parse("자비스, 오늘 날씨 알려줘.") == .show(nil,false))
        precondition(WeatherIntent.parse("군산 날씨 어때?") == .show(gunsan,false))
        precondition(WeatherIntent.parse("내일 서울 날씨 알려줘") == .show(seoul,true))
        precondition(WeatherIntent.parse("군산 내일 날씨 알려줘") == .show(gunsan,true))
        precondition(WeatherIntent.parse("날씨 화면 닫아") == .hide)
        precondition(WeatherIntent.parse("날씨 새로고침") == .refresh)
        precondition(WeatherIntent.parse("파리 날씨 알려줘") == .unsupported)
        precondition(WeatherIntent.parse("날씨 알려주지 마") == nil)
        precondition(WeatherIntent.parse("오늘 아침 뉴스 브리핑해줘") == nil)
        precondition(WeatherPayload.description(95)=="뇌우")
        precondition(WeatherPayload.description(nil)=="상태 미확인")
        precondition(WeatherPayload.kstDay(Date(timeIntervalSince1970:0))=="1970-01-01")
        let fixture=Data(#"{"timezone":"Asia/Seoul","utc_offset_seconds":32400,"current":{"time":"2026-11-21T09:15","temperature_2m":8.5},"hourly":{"time":["2026-11-21T09:00","2026-11-21T10:00"],"temperature_2m":[8,9],"precipitation_probability":[null,20],"weather_code":[0,2]},"daily":{"time":["2026-11-21","2026-11-22"],"temperature_2m_max":[12,13],"temperature_2m_min":[3,4],"precipitation_probability_max":[20,30],"weather_code":[2,3]}}"#.utf8)
        let decoded=try JSONDecoder().decode(WeatherPayload.self,from:fixture)
        precondition(decoded.valid)
        precondition(decoded.nextHours == [1])
        precondition(decoded.hourly.precipitation_probability[0]==nil)
        let now=ISO8601DateFormatter().date(from:"2026-11-21T01:00:00Z")!
        let snap=WeatherSnapshot(town:gunsan,data:decoded,fetched:now)
        let today=WeatherConversation.answer(snap,tomorrow:false,now:now)
        precondition(today.contains("지금 군산") && today.contains("8.5도") && !today.contains("2026"))
        precondition(today.contains("기상 모델 기준") && !today.contains("9.0도"))
        let next=WeatherConversation.answer(snap,tomorrow:true,now:now)
        precondition(next.contains("내일 군산") && next.contains("4.0도") && next.contains("13.0도") && next.contains("30%") && !next.contains("2026"))
        let stale=WeatherConversation.answer(snap,tomorrow:false,now:now.addingTimeInterval(86400))
        precondition(stale.contains("확인하지 못했습니다") && !stale.contains("8.5도"))
        precondition(WeatherConversation.answer(snap,tomorrow:true,now:now.addingTimeInterval(86400)).contains("확인하지 못했습니다"))
        let coldFixture=String(decoding:fixture,as:UTF8.self).replacingOccurrences(of:"8.5",with:"0.7").replacingOccurrences(of:"\"temperature_2m\":0.7",with:"\"temperature_2m\":0.7,\"apparent_temperature\":-2.2,\"weather_code\":2")
        let cold=try JSONDecoder().decode(WeatherPayload.self,from:Data(coldFixture.utf8))
        let coldAnswer=WeatherConversation.answer(.init(town:gunsan,data:cold,fetched:now),tomorrow:false,now:now)
        precondition(coldAnswer.contains("0.7도") && coldAnswer.contains("영하 2.2도") && coldAnswer.contains("구름이 조금 끼어 있어요.") && coldAnswer.contains("따뜻하게 입으세요.") && !coldAnswer.contains("2026"))
        print("PASS: 21 weather routing, data validation, and warm conversational presentation assertions")
        print("EXAMPLE:",coldAnswer)
        if CommandLine.arguments.contains("--live"){
            let client=WeatherClient()
            let start=Date()
            for town in [gunsan,seoul] {
                let value=try await client.fetch(town)
                precondition(value.data.valid)
                precondition(value.data.current.temperature_2m != nil)
                precondition(value.data.daily.time.count==7)
                precondition(value.data.nextHours.count==24)
                print("LIVE",town.name,"current",value.data.current.time,"hourly",value.data.nextHours.count,"daily",value.data.daily.time.count)
            }
            print("LIVE PASS: real Open-Meteo response via Swift client, elapsed",Date().timeIntervalSince(start))
        }
    }
}
