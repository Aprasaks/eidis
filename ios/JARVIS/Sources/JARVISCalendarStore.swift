import Foundation
import UserNotifications

/// Device-owned JARVIS data, persisted independently of Apple Calendar.
/// Do not overwrite unreadable data. All writes are atomic and checked.
@MainActor
final class JARVISCalendarStore: ObservableObject {
    @Published private(set) var entries: [JARVISCalendarRecord] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var notificationMessage = "알림은 선택한 일정에만 설정됩니다."
    @Published private(set) var localRevision = 0
    @Published private(set) var isSyncing = false
    @Published private(set) var conflictCount = 0
    @Published private(set) var syncTimestamp: Date?

    private var pendingIDs: Set<UUID> = []
    private var remoteVersions: [String: String] = [:]

    private struct FileEnvelope: Codable {
        let schema: Int
        let entries: [JARVISCalendarRecord]
        let pendingIDs: [String]?
        let remoteVersions: [String: String]?
    }

    private let fileURL: URL
    private let center: UNUserNotificationCenter?
    private static let supportedReminders = [0, 10, 30, 60]

    init(fileURL: URL? = nil, notifications: UNUserNotificationCenter? = nil) {
        center = notifications
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support.appendingPathComponent("JARVIS", isDirectory: true)
                .appendingPathComponent("calendar-v1.json")
        }
        load()
    }

    func setSyncing(_ value: Bool) { isSyncing = value }

    var activeEntries: [JARVISCalendarRecord] {
        entries.filter(\.isActive).sorted { $0.startAt < $1.startAt }
    }

    func events(on day: Date, calendar: Calendar = .current) -> [JARVISCalendarRecord] {
        activeEntries.filter { calendar.isDate($0.startAt, inSameDayAs: day) }
    }

    func upcoming(from date: Date = Date(), limit: Int = 4) -> [JARVISCalendarRecord] {
        Array(activeEntries.filter { $0.startAt > date || ($0.endAt ?? $0.startAt) > date }.prefix(max(0, limit)))
    }

    func conflicts(for draft: JARVISCalendarRecord) -> [JARVISCalendarRecord] {
        activeEntries.filter { $0.overlaps(draft) }
    }

    @discardableResult
    func save(_ draft: JARVISCalendarRecord) throws -> JARVISCalendarRecord {
        guard !isSyncing else {
            throw JARVISCalendarError.storage("일정 동기화 중이에요. 완료 후 다시 저장해 주세요.")
        }
        guard errorMessage == nil else {
            throw JARVISCalendarError.storage("일정 파일을 읽지 못했어요. 저장을 중단했습니다. 복구 후 다시 시도해 주세요.")
        }
        var copy = draft
        copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.location = copy.location.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.notes = copy.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try copy.validate()

        let now = Date()
        let index = entries.firstIndex { $0.id == copy.id }
        if let index {
            guard entries[index].isActive else {
                throw JARVISCalendarError.invalid("삭제된 일정은 다시 수정할 수 없어요.")
            }
            copy.createdAt = entries[index].createdAt
        } else {
            copy.createdAt = now
        }
        copy.updatedAt = now
        copy.deletedAt = nil

        var next = entries
        if let index { next[index] = copy } else { next.append(copy) }
        let nextPending = pendingIDs.union([copy.id])
        try persist(next, pending: nextPending, versions: remoteVersions)
        pendingIDs = nextPending
        entries = next
        localRevision += 1
        lastSavedAt = now
        Task { await self.scheduleReminder(for: copy) }
        return copy
    }

    func delete(_ id: UUID) throws {
        guard !isSyncing else {
            throw JARVISCalendarError.storage("일정 동기화 중이에요. 완료 후 삭제해 주세요.")
        }
        guard errorMessage == nil else {
            throw JARVISCalendarError.storage("일정 저장소를 읽지 못해 삭제할 수 없어요.")
        }
        guard let index = entries.firstIndex(where: { $0.id == id && $0.isActive }) else {
            throw JARVISCalendarError.invalid("삭제할 일정을 찾을 수 없어요.")
        }
        var next = entries
        next[index].deletedAt = Date()
        next[index].updatedAt = Date()
        let nextPending = pendingIDs.union([id])
        try persist(next, pending: nextPending, versions: remoteVersions)
        pendingIDs = nextPending
        entries = next
        localRevision += 1
        lastSavedAt = Date()
        center?.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // An empty store is valid. Do not invent or import Apple events.
            entries = []
            return
        }
        do {
            let bytes = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(FileEnvelope.self, from: bytes)
            guard [1, 2].contains(envelope.schema),
                  Set(envelope.entries.map(\.id)).count == envelope.entries.count else {
                throw JARVISCalendarError.storage("일정 데이터 버전 또는 중복 ID 오류")
            }
            entries = envelope.entries
            if envelope.schema == 1 {
                // Existing iPhone-only records must be uploaded on the first pair.
                pendingIDs = Set(envelope.entries.map(\.id))
                remoteVersions = [:]
            } else {
                pendingIDs = Set((envelope.pendingIDs ?? []).compactMap(UUID.init(uuidString:)))
                remoteVersions = envelope.remoteVersions ?? [:]
            }
        } catch {
            errorMessage = "저장된 이디스 일정 파일을 읽지 못했어요. 파일을 덮어쓰지 않고 보호하고 있습니다."
        }
    }

    private func persist(_ next: [JARVISCalendarRecord], pending: Set<UUID>,
                         versions: [String: String]) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(FileEnvelope(
                schema: 2, entries: next,
                pendingIDs: pending.map(\.uuidString).sorted(),
                remoteVersions: versions))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            throw JARVISCalendarError.storage("일정을 저장하지 못했어요. 저장 공간과 접근 권한을 확인해 주세요.")
        }
    }

    func rescheduleUpcomingReminders() async {
        for event in upcoming(limit: 50) where event.reminderMinutes != nil {
            await scheduleReminder(for: event, permissionPrompt: false)
        }
    }

    private func scheduleReminder(for event: JARVISCalendarRecord,
                                  permissionPrompt: Bool = true) async {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [event.id.uuidString])
        guard let minutes = event.reminderMinutes else { return }
        guard Self.supportedReminders.contains(minutes) else { return }
        let triggerDate = event.startAt.addingTimeInterval(TimeInterval(-minutes * 60))
        guard triggerDate > Date() else {
            notificationMessage = "일정은 저장됐지만 알림 시각이 지났어요."
            return
        }
        let permission = await center.notificationSettings()
        if permission.authorizationStatus == .notDetermined {
            if permissionPrompt {
                let allowed = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                guard allowed else {
                    notificationMessage = "일정은 저장됐지만 알림 권한이 허용되지 않았어요."
                    return
                }
            } else {
                return
            }
        } else if permission.authorizationStatus == .denied {
            notificationMessage = "일정은 저장됐지만 iPhone에서 EIDIS 알림을 허용해야 해요."
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "EIDIS Calendar"
        content.body = event.title
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: event.id.uuidString,
                                                      content: content, trigger: trigger))
            notificationMessage = "알림 등록 확인 · 일정 \(minutes)분 전"
        } catch {
            notificationMessage = "일정은 저장됐지만 알림 등록에 실패했어요."
        }
    }
}

// MARK: - Peer-to-peer sync (separate from Apple Calendar)
extension JARVISCalendarStore {
    private struct MacRecord: Decodable {
        let id: UUID
        let title: String
        let startAt: String
        let endAt: String?
        let location: String
        let notes: String
        let reminderMinutes: Int?
        let createdAt: String
        let updatedAt: String
        let deletedAt: String?

        func local() throws -> JARVISCalendarRecord {
            guard let start = Self.readTime(startAt),
                  let created = Self.readTime(createdAt),
                  let updated = Self.readTime(updatedAt) else {
                throw JARVISCalendarError.storage("맥에서 받은 일정 날짜가 올바르지 않아요.")
            }
            let end = endAt.flatMap(Self.readTime)
            let deleted = deletedAt.flatMap(Self.readTime)
            guard (endAt == nil || end != nil) &&
                  (deletedAt == nil || deleted != nil) else {
                throw JARVISCalendarError.storage("맥의 일정 시간이 잘못되어 동기화를 중단했어요.")
            }
            let item = JARVISCalendarRecord(id: id, title: title, startAt: start,
                endAt: end, location: location, notes: notes,
                reminderMinutes: reminderMinutes,
                createdAt: created, updatedAt: updated, deletedAt: deleted)
            try item.validate()
            return item
        }

        static func readTime(_ text: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let result = formatter.date(from: text) { return result }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }
    }

    private struct MacResponse: Decodable {
        let acknowledged: [UUID]
        let conflicts: [MacConflict]
        let records: [MacRecord]
    }
    private struct MacConflict: Decodable {
        let id: UUID
        let reason: String
    }

    /// Sends only locally changed records, plus the last trusted Mac version.
    /// This prevents blind overwrites if Mac and iPhone edit the same event.
    func outgoingOperations() throws -> [[String: Any]] {
        guard errorMessage == nil else {
            throw JARVISCalendarError.storage("저장소를 복구한 다음 동기화할 수 있어요.")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try entries.filter { pendingIDs.contains($0.id) }.prefix(150).map { entry in
            let encoded = try encoder.encode(entry)
            guard let record = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                throw JARVISCalendarError.storage("일정 변환 실패")
            }
            return ["record": record,
                    "baseVersion": remoteVersions[entry.id.uuidString] as Any? ?? NSNull()]
        }
    }

    /// Validates the WHOLE snapshot, persists atomically, then updates the UI.
    /// Conflicting local edits remain on the iPhone and are never erased.
    func acceptSync(_ response: [String: Any]) throws -> (received: Int, conflicts: Int) {
        guard errorMessage == nil,
              let data = try? JSONSerialization.data(withJSONObject: response) else {
            throw JARVISCalendarError.storage("동기화 응답을 확인할 수 없어요.")
        }
        let decoded = try JSONDecoder().decode(MacResponse.self, from: data)
        guard decoded.records.count <= 2000,
              Set(decoded.records.map(\.id)).count == decoded.records.count else {
            throw JARVISCalendarError.storage("일정 목록에 중복이 있어 병합하지 않았어요.")
        }
        let validated = try decoded.records.map { (try $0.local(), $0.updatedAt) }
        let acked = Set(decoded.acknowledged)
        let conflicts = Set(decoded.conflicts.map(\.id))
        guard conflicts.isDisjoint(with: acked), acked.isSubset(of: pendingIDs) else {
            throw JARVISCalendarError.storage("일정 동기화 확인 정보가 일치하지 않아요.")
        }
        var next = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var nextPending = pendingIDs.subtracting(acked)
        var nextVersions = remoteVersions
        var received = 0
        for (record, version) in validated {
            if !nextPending.contains(record.id) {
                next[record.id] = record
                nextVersions[record.id.uuidString] = version
                received += 1
            }
            // If a local edit conflicts, deliberately keep its original base.
        }
        for id in acked where !validated.contains(where: { $0.0.id == id }) {
            nextPending.remove(id)
            nextVersions.removeValue(forKey: id.uuidString)
        }
        let nextList = next.values.sorted { $0.startAt < $1.startAt }
        try persist(nextList, pending: nextPending, versions: nextVersions)
        entries = nextList
        pendingIDs = nextPending
        remoteVersions = nextVersions
        conflictCount = conflicts.count
        syncTimestamp = Date()
        Task { await rescheduleUpcomingReminders() }
        return (received, conflicts.count)
    }
}
