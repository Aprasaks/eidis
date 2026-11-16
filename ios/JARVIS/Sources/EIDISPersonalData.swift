import EventKit
import Foundation
import SwiftUI

struct EIDISEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool

    var timeLabel: String {
        if allDay { return "종일" }
        return start.formatted(.dateTime.month(.twoDigits).day(.twoDigits)
            .hour().minute().locale(Locale(identifier: "ko_KR")))
    }
}

struct EIDISTask: Identifiable {
    let id: String
    let title: String
    let due: Date?

    var dueLabel: String {
        guard let due else { return "기한 없음" }
        return due.formatted(.dateTime.month(.twoDigits).day(.twoDigits)
            .locale(Locale(identifier: "ko_KR")))
    }
}

/// Read-only EventKit integration. We request the minimum access Apple offers
/// for reading: full access permission. We never save/delete events or tasks.
@MainActor
final class EIDISPersonalData: ObservableObject {
    @Published private(set) var calendarConnected = false
    @Published private(set) var remindersConnected = false
    @Published private(set) var calendarStatus = "탭하여 연결"
    @Published private(set) var remindersStatus = "탭하여 연결"
    @Published private(set) var events: [EIDISEvent] = []
    @Published private(set) var tasks: [EIDISTask] = []
    @Published private(set) var calendarBusy = false
    @Published private(set) var remindersBusy = false
    @Published private(set) var calendarLoaded = false
    @Published private(set) var remindersLoaded = false

    private let store = EKEventStore()

    init() {
        calendarConnected = Self.isGranted(.event)
        remindersConnected = Self.isGranted(.reminder)
        if calendarConnected { calendarStatus = "불러오는 중" }
        if remindersConnected { remindersStatus = "불러오는 중" }
    }

    private static func isGranted(_ type: EKEntityType) -> Bool {
        EKEventStore.authorizationStatus(for: type) == .fullAccess
    }

    func refreshAuthorized() async {
        if Self.isGranted(.event) {
            await reloadEvents()
        }
        if Self.isGranted(.reminder) {
            await reloadReminders()
        }
    }

    func connectCalendar() async {
        guard !calendarBusy else { return }
        calendarBusy = true
        defer { calendarBusy = false }
        do {
            let granted: Bool
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = Self.isGranted(.event)
            }
            guard granted else {
                calendarConnected = false
                events = []
                calendarLoaded = false
                calendarStatus = "설정에서 캘린더 권한 허용"
                return
            }
            calendarConnected = true
            calendarStatus = "일정 조회 중"
            loadEvents()
        } catch {
            calendarStatus = "캘린더 오류: \(error.localizedDescription)"
        }
    }

    func connectReminders() async {
        guard !remindersBusy else { return }
        remindersBusy = true
        defer { remindersBusy = false }
        do {
            let granted: Bool
            if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
                granted = try await store.requestFullAccessToReminders()
            } else {
                granted = Self.isGranted(.reminder)
            }
            guard granted else {
                remindersConnected = false
                tasks = []
                remindersLoaded = false
                remindersStatus = "설정에서 미리 알림 권한 허용"
                return
            }
            remindersConnected = true
            await loadReminders()
        } catch {
            remindersStatus = "미리 알림 오류: \(error.localizedDescription)"
        }
    }

    func reloadEvents() async {
        guard Self.isGranted(.event) else {
            calendarConnected = false
            calendarLoaded = false
            events = []
            calendarStatus = "탭하여 연결"
            return
        }
        calendarConnected = true
        loadEvents()
    }

    func reloadReminders() async {
        guard Self.isGranted(.reminder) else {
            remindersConnected = false
            remindersLoaded = false
            tasks = []
            remindersStatus = "탭하여 연결"
            return
        }
        remindersConnected = true
        await loadReminders()
    }

    private func loadEvents() {
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now)
            ?? now.addingTimeInterval(7 * 86_400)
        let predicate = store.predicateForEvents(withStart: now, end: horizon,
                                                   calendars: nil)
        let fetched = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        events = fetched.map {
            EIDISEvent(
                id: $0.eventIdentifier ?? UUID().uuidString,
                title: $0.title.isEmpty ? "(제목 없음)" : $0.title,
                start: $0.startDate,
                end: $0.endDate,
                allDay: $0.isAllDay
            )
        }
        calendarLoaded = true
        calendarStatus = events.first.map {
            ($0.allDay ? "종일" : $0.start.formatted(
                .dateTime.hour().minute().locale(Locale(identifier: "ko_KR"))))
                + "  " + $0.title
        } ?? "7일간 일정 없음"
    }

    private func loadReminders() async {
        remindersStatus = "미리 알림 조회 중"
        let predicate = store.predicateForReminders(in: nil)
        let result: [EKReminder]? = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result)
            }
        }
        // Authorization might have been revoked while an asynchronous fetch ran.
        guard Self.isGranted(.reminder) else {
            remindersConnected = false
            remindersLoaded = false
            tasks = []
            remindersStatus = "미리 알림 권한 없음"
            return
        }
        guard let fetched = result else {
            remindersLoaded = false
            remindersStatus = "미리 알림 조회 실패 · 다시 시도"
            return
        }
        tasks = fetched.filter { !$0.isCompleted }.map { item in
            let due = item.dueDateComponents.flatMap(Calendar.current.date(from:))
            return EIDISTask(
                id: item.calendarItemIdentifier,
                title: item.title.isEmpty ? "(제목 없음)" : item.title,
                due: due
            )
        }.sorted {
            let a = $0.due ?? .distantFuture
            let b = $1.due ?? .distantFuture
            if a == b { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return a < b
        }
        remindersLoaded = true
        remindersStatus = tasks.isEmpty ? "미완료 없음" : "미완료 \(tasks.count)개"
    }

    func calendarReadout() -> String {
        guard calendarConnected, calendarLoaded else {
            return "일정 카드를 눌러 iPhone 캘린더를 먼저 연결해 주세요."
        }
        guard let next = events.first else {
            return "앞으로 7일간 예정된 일정이 없습니다."
        }
        return "다음 일정은 \(next.timeLabel), \(next.title)입니다."
    }

    func remindersReadout() -> String {
        guard remindersConnected, remindersLoaded else {
            return "오늘의 작업 카드를 눌러 iPhone 미리 알림을 먼저 연결해 주세요."
        }
        guard !tasks.isEmpty else {
            return "미완료된 미리 알림이 없습니다."
        }
        let examples = tasks.prefix(3).map(\.title).joined(separator: ", ")
        return "미완료된 미리 알림이 \(tasks.count)개 있습니다. \(examples)"
    }
}
