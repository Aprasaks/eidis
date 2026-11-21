import Foundation
@main struct StockTests {
    @MainActor static func main() async throws {
        precondition(StockBoardIntent.parse("자비스, 주식 현황표 띄워봐.") == .show("KR"))
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
        print("PASS: 13 parser, command safety, symbol validation, official response example decoding assertions; no live prices")
    }
}
