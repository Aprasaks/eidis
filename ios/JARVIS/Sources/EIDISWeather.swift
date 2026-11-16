import CoreLocation
import Foundation
import SwiftUI

struct EIDISWeatherReading {
    let temperature: Double
    let feelsLike: Double
    let humidity: Int
    let wind: Double
    let weatherCode: Int
    let fetchedAt: Date
    let provider: String
    let conditionOverride: String?

    var condition: String {
        if let conditionOverride { return conditionOverride }
        switch weatherCode {
        case 0: return "맑음"
        case 1: return "대체로 맑음"
        case 2: return "구름 조금"
        case 3: return "흐림"
        case 45, 48: return "안개"
        case 51, 53, 55: return "이슬비"
        case 56, 57: return "어는 이슬비"
        case 61, 63, 65: return "비"
        case 66, 67: return "어는 비"
        case 71, 73, 75, 77: return "눈"
        case 80, 81, 82: return "소나기"
        case 85, 86: return "눈 소나기"
        case 95, 96, 99: return "뇌우"
        default: return "관측 상태 확인 불가"
        }
    }

    var summary: String {
        "\(Int(temperature.rounded()))° · \(condition)"
    }

    var spoken: String {
        "현재 기온은 \(Int(temperature.rounded()))도, \(condition)입니다. 체감 기온은 \(Int(feelsLike.rounded()))도입니다."
    }

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 3600
    }
}

private struct OpenMeteoResult: Decodable {
    let current: Current

    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let relative_humidity_2m: Int
        let wind_speed_10m: Double
        let weather_code: Int
    }
}

private struct WttrWeatherResult: Decodable {
    let current_condition: [Observation]

    struct Observation: Decodable {
        let temp_C: String
        let FeelsLikeC: String
        let humidity: String
        let windspeedKmph: String
        let weatherCode: String
        let weatherDesc: [Description]
    }

    struct Description: Decodable {
        let value: String
    }
}

private enum EIDISWeatherQueryError: Error {
    case invalidResponse
}

/// Keeps fallback descriptions conservative rather than translating unknown
/// English weather phrases into a more precise claim than the source makes.
private func koreanCondition(_ raw: String) -> String {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if text.contains("thunder") { return "뇌우" }
    if text.contains("snow") || text.contains("blizzard") { return "눈" }
    if text.contains("rain") || text.contains("drizzle") || text.contains("shower") {
        return "비"
    }
    if text.contains("fog") || text.contains("mist") { return "안개" }
    if text.contains("partly") { return "구름 조금" }
    if text.contains("overcast") || text.contains("cloud") { return "흐림" }
    if text.contains("sunny") || text.contains("clear") { return "맑음" }
    return "기상 상태 상세 정보 없음"
}

/// Fetches weather ONLY after a user action. Precise position is shared with
/// Open-Meteo for that lookup; no account, device ID or conversation is sent.
@MainActor
final class EIDISWeatherService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var status = "탭하여 연결"
    @Published private(set) var busy = false
    @Published private(set) var reading: EIDISWeatherReading?
    @Published private(set) var errorMessage: String?

    private let locationManager = CLLocationManager()
    private var explicitlyRequested = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var displayValue: String {
        guard let reading else { return status }
        return reading.isFresh ? reading.summary : "날씨 갱신 필요"
    }

    func connectOrRefresh() {
        guard !busy else { return }
        explicitlyRequested = true
        busy = true
        errorMessage = nil
        status = "현재 위치 확인 중"

        guard CLLocationManager.locationServicesEnabled() else {
            fail("iPhone 위치 서비스가 꺼져 있습니다.")
            return
        }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            fail("설정 → EIDIS → 위치에서 접근을 허용해 주세요.")
        @unknown default:
            fail("위치 권한 상태를 확인할 수 없습니다.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard explicitlyRequested, busy else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            fail("위치 접근이 허용되지 않았습니다.")
        case .notDetermined:
            break
        @unknown default:
            fail("위치 접근 상태를 확인할 수 없습니다.")
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard explicitlyRequested, busy else { return }
        guard let location = locations.last else {
            fail("위치를 확인하지 못했습니다.")
            return
        }
        Task { await requestWeather(coordinate: location.coordinate) }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        guard explicitlyRequested, busy else { return }
        fail("위치 확인 실패: \(error.localizedDescription)")
    }

    private func requestWeather(coordinate: CLLocationCoordinate2D) async {
        status = "Open-Meteo 날씨 조회 중"
        do {
            let observed = try await loadOpenMeteo(coordinate: coordinate)
            accept(observed)
        } catch {
            // This alternate endpoint was tested with live JSON on the Mac.
            // The user is informed before granting location that either
            // provider may receive the coordinate. Never send voice or events.
            status = "보조 날씨 서비스 조회 중"
            do {
                let observed = try await loadWttr(coordinate: coordinate)
                accept(observed)
            } catch {
                fail("날씨 서비스 2곳에 연결하지 못했습니다. 인터넷 연결 후 다시 시도해 주세요.")
            }
        }
    }

    private func loadOpenMeteo(
        coordinate: CLLocationCoordinate2D
    ) async throws -> EIDISWeatherReading {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code"
            ),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let endpoint = url.url else { throw EIDISWeatherQueryError.invalidResponse }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 7
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw EIDISWeatherQueryError.invalidResponse
        }
        let current = try JSONDecoder().decode(OpenMeteoResult.self, from: data).current
        guard (-90...65).contains(current.temperature_2m),
              (-100...70).contains(current.apparent_temperature),
              (0...100).contains(current.relative_humidity_2m),
              current.wind_speed_10m >= 0 else {
            throw EIDISWeatherQueryError.invalidResponse
        }
        return EIDISWeatherReading(
            temperature: current.temperature_2m,
            feelsLike: current.apparent_temperature,
            humidity: current.relative_humidity_2m,
            wind: current.wind_speed_10m,
            weatherCode: current.weather_code,
            fetchedAt: Date(),
            provider: "Open-Meteo",
            conditionOverride: nil
        )
    }

    private func loadWttr(
        coordinate: CLLocationCoordinate2D
    ) async throws -> EIDISWeatherReading {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "wttr.in"
        url.path = "/\\(coordinate.latitude),\\(coordinate.longitude)"
        url.queryItems = [URLQueryItem(name: "format", value: "j1")]
        guard let endpoint = url.url else { throw EIDISWeatherQueryError.invalidResponse }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.setValue("EIDIS-personal-app/0.4 (noncommercial)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw EIDISWeatherQueryError.invalidResponse
        }
        let first = try JSONDecoder().decode(WttrWeatherResult.self, from: data)
            .current_condition.first
        guard let first,
              let temp = Double(first.temp_C),
              let feels = Double(first.FeelsLikeC),
              let humidity = Int(first.humidity),
              let wind = Double(first.windspeedKmph),
              let code = Int(first.weatherCode),
              (-90...65).contains(temp),
              (-100...70).contains(feels),
              (0...100).contains(humidity),
              (0...350).contains(wind) else {
            throw EIDISWeatherQueryError.invalidResponse
        }
        return EIDISWeatherReading(
            temperature: temp,
            feelsLike: feels,
            humidity: humidity,
            wind: wind,
            weatherCode: code,
            fetchedAt: Date(),
            provider: "wttr.in",
            conditionOverride: koreanCondition(first.weatherDesc.first?.value ?? "")
        )
    }

    private func accept(_ observed: EIDISWeatherReading) {
        reading = observed
        status = observed.summary
        errorMessage = nil
        busy = false
        explicitlyRequested = false
    }

    func readout() -> String {
        guard let reading else {
            return "날씨 카드를 눌러 현재 위치와 날씨 정보를 연결해 주세요."
        }
        guard reading.isFresh else {
            return "날씨 정보가 오래됐습니다. 날씨 카드를 눌러 새로 조회해 주세요."
        }
        return reading.spoken
    }

    private func fail(_ message: String) {
        status = "조회 불가"
        errorMessage = message
        busy = false
        explicitlyRequested = false
    }
}
