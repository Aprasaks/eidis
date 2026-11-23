import Foundation

/// The JARVIS calendar is owned by JARVIS, NOT EventKit / Apple Calendar.
/// Codable wire format is intentionally provider-independent for later sync.
/// Deletions are tombstoned so future device sync won't resurrect an event.
struct JARVISCalendarRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var startAt: Date
    var endAt: Date?
    var location: String
    var notes: String
    var reminderMinutes: Int?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        startAt: Date,
        endAt: Date?,
        location: String = "",
        notes: String = "",
        reminderMinutes: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.location = location
        self.notes = notes
        self.reminderMinutes = reminderMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var isActive: Bool { deletedAt == nil }

    func overlaps(_ other: Self) -> Bool {
        isActive && other.isActive && id != other.id &&
        // If one end time is unknown, only warn when starts coincide.
        (endAt != nil && other.endAt != nil
            ? startAt < other.endAt! && endAt! > other.startAt
            : startAt == other.startAt)
    }

    func validate() throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty && title.count <= 120 else {
            throw JARVISCalendarError.invalid("일정 제목을 1~120자로 입력해 주세요.")
        }
        guard location.count <= 200 && notes.count <= 2_000 else {
            throw JARVISCalendarError.invalid("장소는 200자, 메모는 2,000자까지 저장할 수 있어요.")
        }
        if let endAt, (endAt <= startAt || endAt.timeIntervalSince(startAt) > 7 * 86_400) {
            throw JARVISCalendarError.invalid("종료는 시작 이후여야 하며, 일정은 최대 7일이에요.")
        }
        guard startAt.timeIntervalSince1970.isFinite else {
            throw JARVISCalendarError.invalid("날짜가 올바르지 않아요.")
        }
        guard reminderMinutes == nil || [0, 10, 30, 60].contains(reminderMinutes!) else {
            throw JARVISCalendarError.invalid("지원하지 않는 알림 시간이에요.")
        }
    }
}

enum JARVISCalendarError: LocalizedError {
    case invalid(String)
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .storage(let message): message
        }
    }
}

struct JARVISCalendarDraft: Equatable, Identifiable {
    var id: String { "\(Int(startAt.timeIntervalSince1970))-\(title)" }
    let title: String
    let startAt: Date
    let endAt: Date?
    let evidence: String
}

/// Conservative Korean extraction; ambiguous time/date does NOT auto-save.
/// The human must inspect the prefilled editor and explicitly press Save.
enum JARVISCalendarSpeechParser {
    static func requestsCreation(_ input: String) -> Bool {
        let requestedAction = ["잡아줘", "잡아 줘", "등록해", "추가해", "넣어줘", "넣어 줘", "만들어줘", "만들어 줘"]
            .contains { input.contains($0) }
        let calendarContext = ["일정", "미팅", "회의", "약속", "촬영", "예약", "캘린더"]
            .contains { input.contains($0) }
        return requestedAction && calendarContext
    }

    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> JARVISCalendarDraft? {
        let source = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.count <= 400, !source.isEmpty else { return nil }
        // Don't turn passive questions or edit/delete requests into new events.
        guard contains(source, ["잡아줘", "잡아 줘", "등록해", "추가해", "넣어줘", "넣어 줘", "만들어줘", "만들어 줘"]) else {
            return nil
        }

        var working = source
        var day: Date?
        var dayEvidence = ""

        if let match = firstMatch(#"(오늘|내일|모레)"#, in: working),
           let unit = match.parts.first {
            let offset = unit == "오늘" ? 0 : unit == "내일" ? 1 : 2
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
            dayEvidence = unit
            working = working.replacingOccurrences(of: match.full, with: " ")
        } else if let match = firstMatch(#"(?:(\d{4})년\s*)?(\d{1,2})월\s*(\d{1,2})일"#, in: working) {
            let parts = match.parts
            if parts.count == 3,
               let month = Int(parts[1]), let number = Int(parts[2]), (1...12).contains(month), (1...31).contains(number) {
                let year = parts[0].isEmpty ? calendar.component(.year, from: now) : Int(parts[0]) ?? 0
                let components = DateComponents(year: year, month: month, day: number)
                if let candidate = calendar.date(from: components),
                   calendar.component(.year, from: candidate) == year,
                   calendar.component(.month, from: candidate) == month,
                   calendar.component(.day, from: candidate) == number {
                    day = candidate
                    if parts[0].isEmpty, candidate < calendar.startOfDay(for: now) {
                        day = calendar.date(byAdding: .year, value: 1, to: candidate)
                    }
                }
            }
            dayEvidence = match.full
            working = working.replacingOccurrences(of: match.full, with: " ")
        } else if let match = firstMatch(#"(?:이번\s*주\s*|다음\s*주\s*)?(월|화|수|목|금|토|일)요일"#, in: working),
                  let weekday = match.parts.first {
            let names = ["일": 1, "월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7]
            guard let target = names[weekday] else { return nil }
            let base = calendar.startOfDay(for: now)
            let addWeek = match.full.contains("다음") ? 7 : 0
            let current = calendar.component(.weekday, from: now)
            let ahead = (target - current + 7) % 7
            day = calendar.date(byAdding: .day, value: ahead + addWeek, to: base)
            dayEvidence = match.full
            working = working.replacingOccurrences(of: match.full, with: " ")
        }

        guard let day else { return nil }
        let timePattern = #"(오전|오후|아침|저녁|밤)?\s*(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분)?|(?<!\d)(\d{1,2}):(\d{2})(?!\d)"#
        guard let time = firstMatch(timePattern, in: working) else { return nil }
        let groups = time.parts
        var hour: Int?
        var minute = 0
        if groups.count >= 3, let raw = Int(groups[1]) {
            let period = groups[0]
            minute = Int(groups[2]) ?? 0
            if period == "오전" || period == "아침" {
                if (1...12).contains(raw) { hour = raw % 12 }
            } else if ["오후", "저녁", "밤"].contains(period) {
                if (1...12).contains(raw) { hour = (raw % 12) + 12 }
            } else if (13...23).contains(raw) || raw == 0 {
                // "3시" is AM/PM ambiguous; "15시" or "0시" is explicit 24h.
                hour = raw
            }
        } else if groups.count == 5,
                  let parsedHour = Int(groups[3]), let parsedMinute = Int(groups[4]),
                  (0...23).contains(parsedHour) {
            hour = parsedHour
            minute = parsedMinute
        }
        guard let hour, (0...59).contains(minute),
              let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
              calendar.isDate(start, inSameDayAs: day),
              start > now else { return nil }

        working = working.replacingOccurrences(of: time.full, with: " ")
        working = working.replacingOccurrences(of: #"(자비스|애기야|아기야|일정|예약|스케줄|잡아\s*줘|등록해\s*줘|등록해|추가해\s*줘|추가해|넣어\s*줘|만들어\s*줘)"#,
            with: " ", options: .regularExpression)
        working = working.replacingOccurrences(of: #"(^|\s)(에|을|를|좀|해줘|해 줘)(?=\s|$)"#,
            with: " ", options: .regularExpression)
        let title = working.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120 else { return nil }

        return JARVISCalendarDraft(title: title, startAt: start, endAt: nil,
                                   evidence: "\(dayEvidence) \(time.full) · 종료 미정")
    }

    private struct Match {
        let full: String
        let parts: [String]
    }

    private static func firstMatch(_ pattern: String, in input: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let range = Range(match.range, in: input) else { return nil }
        let groups: [String] = (1..<match.numberOfRanges).map { i in
            guard let range = Range(match.range(at: i), in: input) else { return "" }
            return String(input[range])
        }
        return Match(full: String(input[range]), parts: groups)
    }

    private static func contains(_ phrase: String, _ needles: [String]) -> Bool {
        needles.contains(where: phrase.contains)
    }
}
