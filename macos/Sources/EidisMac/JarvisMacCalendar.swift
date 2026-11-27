import Foundation
import SwiftUI

/// JARVIS-owned Mac calendar. No EventKit, no imported Apple events.
/// The installed app's loopback-only Python server is the only write authority.
struct JarvisMacCalendarEvent: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let startAt: String
    let endAt: String?
    let location: String
    let notes: String
    let reminderMinutes: Int?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    var startDate: Date? { JarvisMacCalendarDate.parse(startAt) }
    var endDate: Date? { endAt.flatMap(JarvisMacCalendarDate.parse) }
}

enum JarvisMacCalendarDate {
    static func parse(_ text: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = format.date(from: text) { return result }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: text)
    }
    static func stamp(_ value: Date) -> String {
        let format = ISO8601DateFormatter()
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.formatOptions = [.withInternetDateTime]
        return format.string(from: value)
    }
}

/// Parse only explicit calendar commands, not general discussion of schedules.
/// Voice creates a draft; the user must inspect and press Save.
enum JarvisMacCalendarIntent: Equatable {
    case show
    case new
    case hide

    static func parse(_ text: String) -> Self? {
        let compact = text.lowercased()
            .replacingOccurrences(of: #"^(이디스|자비스|데카|jarvis|eidis)[,\s.!?]*"#,
                                   with: "", options: .regularExpression)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
        let context = ["캘린더", "달력", "내일정", "일정", "스케줄", "약속", "회의", "미팅", "촬영", "병원"]
            .contains { compact.contains($0) }
        guard context else { return nil }
        if ["삭제", "지워", "취소", "변경", "옮겨", "수정"].contains(where: compact.contains) {
            return .show // editing and deletion still require visual selection & approval
        }
        if ["닫아", "닫기", "숨겨", "꺼줘"].contains(where: compact.contains) {
            return .hide
        }
        if ["등록", "추가", "만들어", "생성", "잡아", "넣어"].contains(where: compact.contains) {
            return .new
        }
        if ["보여", "열어", "띄워", "확인", "오늘", "이번주", "내일", "이번달", "알려",
            "목록", "뭐있", "어떤", "일정은", "일정이"]
            .contains(where: compact.contains) {
            return .show
        }
        return nil
    }
}

enum JarvisMacCalendarDraft {
    /// Strictly interpret supported Korean dates and meridiem.
    /// Return nil if the date/time cannot be determined rather than guessing.
    static func extract(_ text: String, now: Date = Date(), calendar: Calendar = .current)
        -> (title: String, start: Date)?
    {
        let datePattern = #"(오늘|내일|모레)|(?:(\d{4})년\s*)?(\d{1,2})월\s*(\d{1,2})일"#
        guard let r = try? NSRegularExpression(pattern: datePattern),
              let dateMatch = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let dateRange = Range(dateMatch.range, in: text) else { return nil }
        let dateEvidence = String(text[dateRange])
        var day: Date?
        switch dateEvidence {
        case "오늘": day = calendar.startOfDay(for: now)
        case "내일": day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        case "모레": day = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))
        default:
            func component(_ index: Int) -> Int? {
                guard let range = Range(dateMatch.range(at: index), in: text) else { return nil }
                return Int(text[range])
            }
            if let month = component(3), let d = component(4),
               (1...12).contains(month), (1...31).contains(d) {
                let year = component(2) ?? calendar.component(.year, from: now)
                let pieces = DateComponents(year: year, month: month, day: d)
                if let candidate = calendar.date(from: pieces),
                   calendar.component(.month, from: candidate) == month,
                   calendar.component(.day, from: candidate) == d {
                    day = candidate
                    if component(2) == nil, candidate < calendar.startOfDay(for: now) {
                        day = calendar.date(byAdding: .year, value: 1, to: candidate)
                    }
                }
            }
        }
        guard let day else { return nil }
        let timePattern = #"(오전|오후|아침|저녁|밤)?\s*(\d{1,2})시(?:\s*(\d{1,2})분)?|(?<!\d)(\d{1,2}):(\d{2})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: timePattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let timeRange = Range(match.range, in: text) else { return nil }
        func field(_ i: Int) -> String {
            guard let range = Range(match.range(at: i), in: text) else { return "" }
            return String(text[range])
        }
        var hour: Int?
        var minute = 0
        if let h = Int(field(2)) {
            let meridiem = field(1)
            minute = Int(field(3)) ?? 0
            if ["오전", "아침"].contains(meridiem), (1...12).contains(h) {
                hour = h % 12
            } else if ["오후", "저녁", "밤"].contains(meridiem), (1...12).contains(h) {
                hour = (h % 12) + 12
            } else if meridiem.isEmpty && ((13...23).contains(h) || h == 0) {
                hour = h
            }
        } else if let h = Int(field(4)), let m = Int(field(5)), (0...23).contains(h) {
            hour = h
            minute = m
        }
        guard let hour, (0...59).contains(minute),
              let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
              calendar.isDate(start, inSameDayAs: day) else { return nil }

        var remainder = text
        remainder.removeSubrange(timeRange)
        if let found = remainder.range(of: dateEvidence) { remainder.removeSubrange(found) }
        remainder = remainder.replacingOccurrences(
            of: #"(이디스|자비스|내|일정|캘린더|스케줄|잡아\s*줘|등록해\s*줘|추가해\s*줘|만들어\s*줘|넣어\s*줘|잡아줘|등록해|추가해|만들어|넣어)"#,
            with: " ", options: .regularExpression)
        remainder = remainder.replacingOccurrences(of: #"(?<=\s)(에|을|를|좀)(?=\s|$)"#,
                                                   with: " ", options: .regularExpression)
        let title = remainder.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty && title.count <= 120 else { return nil }
        return (title, start)
    }
}

@MainActor
final class JarvisMacCalendarStore: ObservableObject {
    static let shared = JarvisMacCalendarStore()

    @Published var visible = false
    @Published var presentingNew = false
    @Published var draftTitle = ""
    @Published var draftStart = Date()
    @Published private(set) var entries: [JarvisMacCalendarEvent] = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published private(set) var status = "EIDIS 일정 로컬 서버 확인 전"
    @Published private(set) var lastLoadedAt: Date?

    private let session: URLSession
    private let base = URL(string: "http://127.0.0.1:8765")!

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 7
        session = URLSession(configuration: config)
    }

    struct Listing: Decodable { let items: [JarvisMacCalendarEvent]; let source: String; let sync: String }
    private struct ErrorReply: Decodable { let error: String }
    private struct ItemReply: Decodable { let event: JarvisMacCalendarEvent }
    private struct DeletedReply: Decodable { let deleted: Bool }

    func close() {
        visible = false
        presentingNew = false
    }

    func show(_ intent: JarvisMacCalendarIntent, phrase: String) async -> String {
        switch intent {
        case .hide:
            visible = false
            presentingNew = false
            return "DECHIVE, 이디스 캘린더를 닫았습니다."
        case .new:
            visible = true
            if let draft = JarvisMacCalendarDraft.extract(phrase) {
                draftTitle = draft.title
                draftStart = draft.start
                status = "음성에서 날짜·제목을 추출했어요. 확인 후 저장해 주세요. 종료시간은 미정으로 시작합니다."
            } else {
                draftTitle = ""
                draftStart = Date()
                status = "날짜 또는 시간이 모호할 수 있어요. 직접 확인한 다음 저장해 주세요."
            }
            presentingNew = true
            await refresh()
            return "DECHIVE, 새 일정 작성 화면을 열었습니다. 날짜, 시작시간, 종료시간 미정 여부, 제목, 장소, 상세내용을 확인하고 저장을 눌러 주세요."
        case .show:
            visible = true
            await refresh()
            if lastLoadedAt == nil { return "DECHIVE, 이디스 캘린더 서버에 연결하지 못했습니다. 일정 화면의 연결 상태를 확인해 주세요." }
            return "DECHIVE, 이디스 캘린더를 열었어요. 현재 실제 저장된 일정은 \(entries.count)건입니다."
        }
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let (data, http) = try await send(path: "/api/calendar?limit=200", payload: nil)
            guard http == 200 else { throw serviceError(http, data: data) }
            let fetched = try JSONDecoder().decode(Listing.self, from: data)
            entries = fetched.items.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            status = "EIDIS 자체 일정 \(entries.count)건 · Mac SQLite · iPhone 동기화 미연결"
            lastLoadedAt = Date()
        } catch {
            entries = []
            lastLoadedAt = nil
            status = "일정 조회 실패: \(error.localizedDescription)"
        }
    }

    func create(title: String, start: Date, end: Date?, location: String, detail: String) async -> Bool {
        await change(path: "/api/calendar/create", fields: [
            "title": title, "startAt": JarvisMacCalendarDate.stamp(start),
            "endAt": end.map(JarvisMacCalendarDate.stamp) ?? NSNull(),
            "location": location, "notes": detail,
        ], successText: "일정을 실제 데이터베이스에 저장했어요.")
    }

    func update(_ existing: JarvisMacCalendarEvent, title: String, start: Date,
                end: Date?, location: String, detail: String) async -> Bool {
        await change(path: "/api/calendar/update", fields: [
            "id": existing.id, "expectedUpdatedAt": existing.updatedAt,
            "title": title, "startAt": JarvisMacCalendarDate.stamp(start),
            "endAt": end.map(JarvisMacCalendarDate.stamp) ?? NSNull(),
            "location": location, "notes": detail,
        ], successText: "일정 수정 내용을 데이터베이스에 저장했어요.")
    }

    func delete(_ existing: JarvisMacCalendarEvent) async -> Bool {
        await change(path: "/api/calendar/delete", fields: [
            "id": existing.id, "expectedUpdatedAt": existing.updatedAt
        ], successText: "선택한 일정 삭제가 데이터베이스에서 확인됐어요.")
    }

    private func change(path: String, fields: [String: Any], successText: String) async -> Bool {
        guard !saving else { return false }
        saving = true
        defer { saving = false }
        do {
            let (data, statusCode) = try await send(path: path, payload: fields)
            guard statusCode == 200 else { throw serviceError(statusCode, data: data) }
            if path == "/api/calendar/delete" {
                guard (try JSONDecoder().decode(DeletedReply.self, from: data)).deleted else {
                    throw URLError(.badServerResponse)
                }
            } else {
                _ = try JSONDecoder().decode(ItemReply.self, from: data)
            }
            await refresh()
            guard lastLoadedAt != nil else {
                status = "저장 API 응답은 성공했지만 다시 조회하지 못했어요. 확인이 필요합니다."
                return false
            }
            status = successText
            JarvisMacNearbyCalendar.shared.changed()
            return true
        } catch {
            status = "변경 실패 · \(error.localizedDescription)"
            return false
        }
    }

    private func serviceError(_ statusCode: Int, data: Data) -> NSError {
        let message = (try? JSONDecoder().decode(ErrorReply.self, from: data))?.error
            ?? "로컬 서버 HTTP \(statusCode)"
        return NSError(domain: "JARVISCalendar", code: statusCode,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func send(path: String, payload: [String: Any]?) async throws -> (Data, Int) {
        guard let url = URL(string: path, relativeTo: base) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let payload {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count < 1_000_000 else {
            throw URLError(.badServerResponse)
        }
        return (data, http.statusCode)
    }
}
