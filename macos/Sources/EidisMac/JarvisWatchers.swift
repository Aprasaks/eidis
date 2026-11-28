import Foundation

/// 기획서 P4 · 먼저 말 걸기 (watchers). 1분마다 확인하고, 조건이 맞을 때만 한 번 알린다.
/// - 일정: 시작 10분 전 ("Your meeting starts in 10 minutes.")
/// - 날씨: 1시간 안에 비 (기본 지역 · Open-Meteo 강수확률 60% 이상)
/// 말하기·대기열·폰 알림은 완료 알림(JarvisCompletionNotices)과 같은 길을 쓴다. 밤 00~08시에는 말하지 않는다.
@MainActor
final class JarvisWatchers {
    static let shared = JarvisWatchers()
    private var loop: Task<Void, Never>?
    private var announcedEvents = Set<String>()
    private var lastRainNotice: Date?

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkCalendar()
                await self?.checkRain()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    private static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private func checkCalendar() async {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let start = day.string(from: now.addingTimeInterval(-86_400))
        let end = day.string(from: now.addingTimeInterval(2 * 86_400))
        guard let url = URL(string: "http://127.0.0.1:8765/api/calendar?start=\(start)&end=\(end)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { return }
        for item in items {
            guard let id = item["id"] as? String, !announcedEvents.contains(id),
                  let title = item["title"] as? String,
                  let startAt = (item["startAt"] as? String).flatMap(Self.iso) else { continue }
            let minutes = startAt.timeIntervalSince(now) / 60
            guard (8.5...10.5).contains(minutes) else { continue }
            announcedEvents.insert(id)
            let place = (item["location"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let text = JarvisConversationLanguage.english
                ? "\(title) starts in 10 minutes" + (place.map { ", at \($0)." } ?? ".")
                : "10분 뒤에 \(title) 일정이에요" + (place.map { " (\($0))." } ?? ".")
            // 영어 모드에서 한국어 일정 제목은 로컬 Qwen으로 영어 문장으로 바꿔 말한다
            var spoken = text
            if JarvisConversationLanguage.english, text.range(of: #"\p{Hangul}"#, options: .regularExpression) != nil,
               let english = await JarvisEnglishCommand.toEnglish(text) { spoken = english }
            JarvisCompletionNotices.shared.announce(agent: "Calendar", text: spoken, pushTitle: "📅 10분 뒤 일정")
        }
    }

    private func checkRain() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        guard (8..<23).contains(hour), calendar.component(.minute, from: now) % 15 == 0 else { return }
        if let last = lastRainNotice, now.timeIntervalSince(last) < 3 * 3600 { return }
        let town = WeatherTown.towns.first { $0.name == UserDefaults.standard.string(forKey: "jarvis.weather.defaultTown") }
            ?? WeatherTown.towns[0]
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [.init(name: "latitude", value: String(town.latitude)),
                            .init(name: "longitude", value: String(town.longitude)),
                            .init(name: "current", value: "precipitation"),
                            .init(name: "hourly", value: "precipitation_probability"),
                            .init(name: "forecast_hours", value: "2"),
                            .init(name: "timezone", value: "Asia/Seoul")]
        guard let url = parts.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hourly = object["hourly"] as? [String: Any],
              let chances = hourly["precipitation_probability"] as? [Any] else { return }
        let raining = ((object["current"] as? [String: Any])?["precipitation"] as? Double ?? 0) > 0
        let nextHour = chances.compactMap { $0 as? Int }.max() ?? 0
        guard !raining, nextHour >= 60 else { return }
        lastRainNotice = now
        let text = JarvisConversationLanguage.english
            ? "Rain is likely in \(["군산": "Gunsan", "서울": "Seoul", "고양": "Goyang"][town.name] ?? town.name) within the hour (\(nextHour)%)."
            : "한 시간 안에 \(town.name)에 비가 올 것 같아요 (강수확률 \(nextHour)%)."
        JarvisCompletionNotices.shared.announce(agent: "Weather", text: text, pushTitle: "☔️ 곧 비")
    }
}
