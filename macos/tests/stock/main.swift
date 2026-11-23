import Foundation
@main struct StockTests {
    @MainActor static func main() async throws {
        precondition(StockBoardIntent.parse("자비스, 주식 현황표 띄워봐.") == .dualTop10(.value))
        // Real-world spoken variants that previously fell through to Qwen.
        for sentence in ["주식 현황표 열어봐", "주식 현황표를 열어줘", "주식 현황표 좀 열어봐",
                         "애기야 주식 현황표 열어봐", "자비스, 주식 현황표 열어봐?",
                         "주식창 띄워봐", "주식 화면 보여줘", "주식 대시보드 열어봐",
                         "증권 현황 열어줘", "증권창 켜줘", "주식 현황표 보여줄래"] {
            precondition(StockBoardIntent.parse(sentence) == .dualTop10(.value), "Not opening stock board: \(sentence)")
        }
        for sentence in ["미국 주식 현황표 열어봐", "미국 증시 현황판 보여줘"] {
            precondition(StockBoardIntent.parse(sentence) == .show("US"), "US stock board: \(sentence)")
        }
        for sentence in ["주식 현황표 열지 마", "주식 현황표 말고 대시보드 열어봐",
                         "주식 현황표는 어떻게 만들어?", "주식 현황표를 매수해줘",
                         "주식 현황표를 열어준다고 했지?", "오늘 주식시장 뉴스 검색해줘"] {
            precondition(StockBoardIntent.parse(sentence) == nil, "False stock board opening: \(sentence)")
        }

        precondition(StockBoardIntent.parse("국내 미국 탑 10 주식 같이 보여줘") == .dualTop10(.value))
        precondition(StockBoardIntent.parse("국내와 미국 거래량 상위 10종목 열어줘") == .dualTop10(.volume))
        precondition(StockBoardIntent.parse("양쪽 급등주 TOP10 띄워봐") == .dualTop10(.gainers))
        precondition(StockBoardIntent.parse("국내와 미국 급락주 TOP10 보여줘") == .dualTop10(.losers))
        precondition(StockBoardIntent.parse("실시간 조회수 높은 주식 열어줘") == .mostViewedUnavailable)
        precondition(StockBoardIntent.parse("많이 보는 종목 보여줘") == .mostViewedUnavailable)
        precondition(StockBoardIntent.parse("주식 조회수 순위 매수해") == nil)
        precondition(StockTopMetric.gainers.duration == "1d")
        precondition(StockTopMetric.losers.duration == "1d")
        precondition(StockTopMetric.value.duration == "realtime")
        precondition(StockBoardIntent.parse("대시보드 열어줘") == nil)
        precondition(StockBoardIntent.parse("미국 주식으로 바꿔봐") == .show("US"))
        precondition(StockBoardIntent.parse("오늘 거래량 높은 종목 20개 띄워봐") == .ranking("KR","MARKET_TRADING_VOLUME",20))
        precondition(StockBoardIntent.parse("삼성전자랑 SK하이닉스 비교해 봐") == .symbols(["000660","005930"]))
        precondition(StockBoardIntent.parse("삼성전자 현재가 알려줘") == .symbols(["005930"]))
        precondition(StockBoardIntent.parse("주식 현황표 닫아") == .hide)
        precondition(StockBoardIntent.parse("삼성전자 매수해줘") == nil)
        precondition(StockBoardIntent.parse("주식 현황표 띄우지마") == nil)
        precondition(StockBoardIntent.parse("오늘 아침 뉴스 브리핑해줘") == nil)
        precondition(JarvisStockBoard.cleanSymbols("005930, nvda, NVDA") == ["005930","NVDA"])
        precondition(JarvisStockBoard.cleanSymbols("https://invalid") == nil)
        let quote=Data(#"{"result":[{"symbol":"005930","timestamp":"2026-03-25T09:30:00.123+09:00","lastPrice":"72000","currency":"KRW"}]}"#.utf8)
        let result=try JSONDecoder().decode(StockEnvelope<[StockQuote]>.self,from:quote)
        precondition(result.result.first?.lastPrice=="72000")
        let ranking=Data(#"{"result":{"rankedAt":"2026-06-10T14:30:00+09:00","rankings":[{"rank":1,"symbol":"005930","currency":"KRW","price":{"lastPrice":"56500","basePrice":"55800","changeRate":"0.0125"},"tradingVolume":"18432100","tradingAmount":"1041436650000"}]}}"#.utf8)
        let ranks=try JSONDecoder().decode(StockEnvelope<StockRanks>.self,from:ranking)
        precondition(ranks.result.rankings.first?.price.changeRate=="0.0125")
        precondition(ranks.result.rankings.first?.tradingAmount=="1041436650000")
        precondition(StockBoardIntent.parse("관심 종목에 삼성전자 추가해") == .addWatch(["005930"]))
        precondition(StockBoardIntent.parse("관심 종목에서 엔비디아 빼줘") == .removeWatch(["NVDA"]))
        precondition(StockBoardIntent.parse("관심 종목 보여줘") == .watchlist)
        precondition(StockBoardIntent.parse("삼성전자 1분봉 띄워봐") == .chart("005930","1m"))
        precondition(StockBoardIntent.parse("엔비디아 일봉 보여줘") == .chart("NVDA","1d"))
        precondition(StockBoardIntent.parse("삼성전자 5분봉 띄워봐") == nil)
        let sample=Data(#"{"result":{"today":{"date":"2026-03-25","integrated":{"regularMarket":{"startTime":"2026-03-25T09:00:00+09:00","endTime":"2026-03-25T15:30:00+09:00"}}},"previousBusinessDay":null,"nextBusinessDay":null}}"#.utf8)
        let calendar=try JSONDecoder().decode(StockEnvelope<StockMarketCalendar>.self,from:sample).result
        precondition(calendar.status(StockMarketDay.parse("2026-03-25T10:00:00+09:00")!,market:"KR") == "정규장 예정 시간대")
        precondition(calendar.status(StockMarketDay.parse("2026-03-25T15:30:00+09:00")!,market:"KR") == "거래 예정 시간 외")
        precondition(calendar.status(StockMarketDay.parse("2026-03-26T10:00:00+09:00")!,market:"KR") == "달력 날짜 갱신 필요")
        let holiday=try JSONDecoder().decode(StockMarketCalendar.self,from:Data(#"{"today":{"date":"2026-05-05","integrated":null}}"#.utf8))
        precondition(holiday.status(StockMarketDay.parse("2026-05-05T10:00:00+09:00")!,market:"KR") == "휴장일 · 공식 달력")
        let us=try JSONDecoder().decode(StockMarketCalendar.self,from:Data(#"{"today":{"date":"2026-03-25","regularMarket":{"startTime":"2026-03-25T22:30:00+09:00","endTime":"2026-03-26T05:00:00+09:00"}}}"#.utf8))
        precondition(us.status(StockMarketDay.parse("2026-03-26T02:00:00+09:00")!,market:"US") == "정규장 예정 시간대")
        let candles=try JSONDecoder().decode(StockEnvelope<StockCandlePage>.self,from:Data(#"{"result":{"candles":[{"timestamp":"2026-03-25T09:32:00+09:00","closePrice":"72050","volume":"15200","currency":"KRW"}],"nextBefore":null}}"#.utf8))
        precondition(candles.result.candles.first?.date != nil && candles.result.candles.first?.close == 72050)
        print("PASS: 25 assertions; commands, official response examples, market-calendar time zones, chart decoding. No live quote verification.")
    }
}
