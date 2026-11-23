import Foundation
import SwiftUI
import AlarmKit

/// AlarmKit schedules the system alarm even when the JARVIS process is not
/// running. Unlike a local notification it is a genuine system alarm.
@available(iOS 26.0, *)
private struct JARVISAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
@MainActor
enum JARVISAlarmSystem {
    static let manager = AlarmManager.shared

    static func requestPermission() async throws {
        let status = try await manager.requestAuthorization()
        guard status == .authorized else { throw JARVISAlarmError.denied }
    }

    static func install(_ spec: JARVISAlarmRecord) async throws {
        try spec.validate()
        let schedule: Alarm.Schedule
        if spec.weekdays.isEmpty {
            guard let nextDate = spec.nextFire() else {
                throw JARVISAlarmError.invalid("다음 알람 시각을 계산할 수 없어요.")
            }
            schedule = .fixed(nextDate)
        } else {
            let days = spec.weekdays.compactMap { number -> Locale.Weekday? in
                switch number {
                case 1: .sunday
                case 2: .monday
                case 3: .tuesday
                case 4: .wednesday
                case 5: .thursday
                case 6: .friday
                case 7: .saturday
                default: nil
                }
            }
            guard days.count == spec.weekdays.count else {
                throw JARVISAlarmError.invalid("반복 요일이 올바르지 않아요.")
            }
            let time = Alarm.Schedule.Relative.Time(hour: spec.hour, minute: spec.minute)
            schedule = .relative(.init(time: time, repeats: .weekly(days)))
        }

        // iOS 26.1+ owns the system stop/X control. It cannot be renamed.
        // Add a DISTINCT owner-confirmed wake-up action instead of claiming
        // a generic stop means the user has actually gotten out of bed.
        let awakeButton = AlarmButton(
            text: "일어났어", textColor: .white,
            systemImageName: "checkmark.circle.fill"
        )
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: spec.title),
                secondaryButton: awakeButton,
                secondaryButtonBehavior: .custom
            )
        } else {
            // Prior to 26.1, the stop label is actually customizable.
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: spec.title),
                stopButton: AlarmButton(text: "끄기", textColor: .white,
                                        systemImageName: "stop.fill"),
                secondaryButton: awakeButton,
                secondaryButtonBehavior: .custom
            )
        }
        let attributes = AlarmAttributes<JARVISAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration<JARVISAlarmMetadata>.alarm(
            schedule: schedule,
            attributes: attributes,
            secondaryIntent: JARVISWakeConfirmationIntent(alarmID: spec.id.uuidString),
            sound: .default
        )
        _ = try await manager.schedule(id: spec.id, configuration: configuration)
    }

    static func remove(_ id: UUID) throws {
        try manager.cancel(id: id)
    }

    static func isInstalled(_ id: UUID) throws -> Bool {
        try manager.alarms.contains(where: { $0.id == id })
    }
}

/// An independent persisted definition of the alarms JARVIS owns.
/// An alarm is displayed as active only when the system has confirmed it.
@MainActor
final class JARVISAlarmStore: ObservableObject {
    @Published private(set) var records: [JARVISAlarmRecord] = []
    @Published private(set) var saving = false
    @Published private(set) var status = ""
    @Published private(set) var readError: String?
    @Published private(set) var permissionStatus = ""
    @Published private(set) var refreshedAt: Date?

    private struct Envelope: Codable {
        var schema: Int
        var records: [JARVISAlarmRecord]
    }

    private let fileURL: URL
    private let maximum = 30

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask)[0]
            self.fileURL = support.appendingPathComponent("JARVIS", isDirectory: true)
                .appendingPathComponent("alarms-v1.json")
        }
        load()
    }

    var sorted: [JARVISAlarmRecord] {
        records.sorted { ($0.hour, $0.minute, $0.createdAt) <
                         ($1.hour, $1.minute, $1.createdAt) }
    }

    var activeCount: Int { records.filter(\.isEnabled).count }

    var alarmSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    func refresh() {
        guard readError == nil else { return }
        guard #available(iOS 26.0, *) else {
            permissionStatus = "iOS 26 이상 필요"
            return
        }
        let system = JARVISAlarmSystem.manager
        switch system.authorizationState {
        case .authorized: permissionStatus = ""
        case .denied: permissionStatus = "알람 권한이 꺼져 있습니다."
        case .notDetermined: permissionStatus = "첫 알람을 저장하면 알람 권한을 요청합니다."
        @unknown default: permissionStatus = "알람 권한 상태를 확인해 주세요."
        }
        if system.authorizationState == .authorized {
            let valid: Set<UUID>
            do {
                valid = Set(try system.alarms.map(\.id))
            } catch {
                status = "시스템 알람 목록을 확인하지 못했어요. 기존 설정은 변경하지 않았습니다."
                return
            }
            let stale = records.filter { $0.isEnabled && !valid.contains($0.id) }
            if !stale.isEmpty {
                var next = records
                for index in next.indices where next[index].isEnabled && !valid.contains(next[index].id) {
                    next[index].isEnabled = false
                }
                do {
                    try persist(next)
                    records = next
                    status = "\(stale.count)개 알람이 시스템에 등록되어 있지 않아 꺼진 상태로 표시합니다."
                } catch {
                    status = error.localizedDescription
                }
            }
        }
        refreshedAt = Date()
    }

    func save(_ input: JARVISAlarmRecord) async -> Bool {
        guard !saving else { return false }
        saving = true
        defer { saving = false }
        do {
            guard readError == nil else {
                throw JARVISAlarmError.storage("알람 파일을 읽지 못해 변경할 수 없어요.")
            }
            var spec = input
            spec.title = spec.title.trimmingCharacters(in: .whitespacesAndNewlines)
            spec.weekdays.sort()
            try spec.validate()
            let before = records.first(where: { $0.id == spec.id })
            guard before != nil || records.count < maximum else {
                throw JARVISAlarmError.invalid("알람은 최대 30개까지 등록할 수 있어요.")
            }
            if let before {
                spec.createdAt = before.createdAt
            }
            var next = records
            if let index = next.firstIndex(where: { $0.id == spec.id }) {
                next[index] = spec
            } else {
                next.append(spec)
            }

            guard #available(iOS 26.0, *) else { throw JARVISAlarmError.unsupported }
            // First confirm system authorization; do not remove an existing
            // functioning alarm because of a newly denied permission.
            if spec.isEnabled { try await JARVISAlarmSystem.requestPermission() }
            var cancelledOld = false
            if let before, before.isEnabled, try JARVISAlarmSystem.isInstalled(spec.id) {
                try JARVISAlarmSystem.remove(spec.id)
                cancelledOld = true
            }
            do {
                if spec.isEnabled {
                    try await JARVISAlarmSystem.install(spec)
                    guard try JARVISAlarmSystem.isInstalled(spec.id) else {
                        throw JARVISAlarmError.system("시스템 알람 등록을 확인하지 못했어요.")
                    }
                }
                try persist(next)
            } catch {
                // Never claim success after an OS or persistence failure.
                if (try? JARVISAlarmSystem.isInstalled(spec.id)) == true {
                    try? JARVISAlarmSystem.remove(spec.id)
                }
                if let before, cancelledOld {
                    try? await JARVISAlarmSystem.install(before)
                }
                throw error
            }
            records = next
            status = spec.isEnabled ? "iPhone 시스템 알람 등록 확인 완료" : "알람이 꺼졌어요."
            refreshedAt = Date()
            return true
        } catch {
            status = "알람 저장 실패: \(error.localizedDescription)"
            return false
        }
    }

    func setEnabled(_ id: UUID, to enabled: Bool) async -> Bool {
        guard var current = records.first(where: { $0.id == id }) else { return false }
        if current.isEnabled == enabled { return true }
        current.isEnabled = enabled
        return await save(current)
    }

    func delete(_ id: UUID) async -> Bool {
        guard !saving else { return false }
        saving = true
        defer { saving = false }
        do {
            guard readError == nil else {
                throw JARVISAlarmError.storage("알람 파일에 문제가 있어 삭제할 수 없어요.")
            }
            guard let previous = records.first(where: { $0.id == id }) else {
                throw JARVISAlarmError.invalid("삭제할 알람을 찾을 수 없어요.")
            }
            guard #available(iOS 26.0, *) else { throw JARVISAlarmError.unsupported }
            let wasInstalled = try JARVISAlarmSystem.isInstalled(id)
            if wasInstalled {
                try JARVISAlarmSystem.remove(id)
            }
            let next = records.filter { $0.id != id }
            do {
                try persist(next)
            } catch {
                if wasInstalled, previous.isEnabled {
                    try? await JARVISAlarmSystem.install(previous)
                }
                throw error
            }
            records = next
            status = "알람을 삭제했습니다."
            refreshedAt = Date()
            return true
        } catch {
            status = "삭제 실패: \(error.localizedDescription)"
            return false
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(Envelope.self, from: data)
            guard decoded.schema == 1 && decoded.records.count <= maximum &&
                    Set(decoded.records.map(\.id)).count == decoded.records.count else {
                throw JARVISAlarmError.storage("알람 파일 형식 또는 ID가 올바르지 않아요.")
            }
            for record in decoded.records { try record.validate() }
            records = decoded.records
        } catch {
            readError = "알람 설정 파일을 읽지 못했습니다. 기존 파일을 보호하고 있어요."
        }
    }

    private func persist(_ list: [JARVISAlarmRecord]) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory,
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Envelope(schema: 1, records: list))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            throw JARVISAlarmError.storage("알람 설정을 저장하지 못했어요.")
        }
    }
}
