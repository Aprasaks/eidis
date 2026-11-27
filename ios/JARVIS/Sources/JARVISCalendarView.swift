import SwiftUI

/// JARVIS's OWN calendar, not a wrapper around the iPhone calendar.
struct JARVISCalendarView: View {
    @ObservedObject var store: JARVISCalendarStore
    @ObservedObject var nearby: JARVISMobileNearbyCalendar
    @State private var showingPairing = false
    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()
    @State private var presentingNew = false
    @State private var editing: JARVISCalendarRecord?
    @State private var statusText = ""

    private let calendar = Calendar.current
    private let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("일정")
                        .font(.system(size: 27, weight: .semibold))
                        .tracking(-1)
                }
                Spacer(minLength: 8)
                Button {
                    showingPairing = true
                    if !nearby.connected { nearby.startSearch() }
                } label: {
                    Image(systemName: nearby.connected ? "checkmark.circle" : "link")
                        .font(.system(size: 18))
                        .foregroundStyle(JARVISPalette.gold)
                        .frame(width: 36, height: 43)
                }
                .accessibilityLabel("Mac 연결 및 동기화")
                Button {
                    presentingNew = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(JARVISPalette.black)
                        .frame(width: 43, height: 43)
                        .background(JARVISPalette.gold, in: Circle())
                }
                .accessibilityLabel("이디스 새 일정 추가")
            }
            .padding(.top, 22)

            if nearby.connected || nearby.syncing || store.conflictCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: store.conflictCount > 0 ? "exclamationmark.triangle" :
                          nearby.syncing ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    Text(nearby.status)
                        .lineLimit(2)
                }
                .font(.system(size: 11))
                .foregroundStyle(JARVISPalette.goldDim)
            }

            VStack(spacing: 14) {
                monthHeader
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(weekdayLabels, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(JARVISPalette.muted)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayButton(day)
                        } else {
                            Color.clear.frame(height: 34)
                        }
                    }
                }
            }
            .padding(13)
            .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17)
                .stroke(JARVISPalette.panelEdge, lineWidth: 0.7))

            HStack(alignment: .firstTextBaseline) {
                Text(selectedDate.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR"))))
                    .font(.system(size: 19, weight: .semibold))
                Spacer()
                Text("\(store.events(on: selectedDate).count)건")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(JARVISPalette.gold)
            }

            let selected = store.events(on: selectedDate)
            if selected.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 25, weight: .ultraLight))
                        .foregroundStyle(JARVISPalette.goldDim)
                    Text("이날 등록된 일정이 없어요.")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 15))
            } else {
                ForEach(selected) { record in
                    Button { editing = record } label: {
                        HStack(alignment: .top, spacing: 13) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(JARVISPalette.gold)
                                .frame(width: 3, height: 42)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(JARVISPalette.white)
                                Text("\(record.startAt.formatted(date: .omitted, time: .shortened)) – \(record.endAt?.formatted(date: .omitted, time: .shortened) ?? "종료 미정")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(JARVISPalette.muted)
                                if !record.location.isEmpty {
                                    Label(record.location, systemImage: "mappin")
                                        .font(.system(size: 11))
                                        .foregroundStyle(JARVISPalette.muted)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(JARVISPalette.goldDim)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(JARVISPalette.gold)
            }
            if store.activeEntries.contains(where: { $0.reminderMinutes != nil }) {
                Text(store.notificationMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(JARVISPalette.muted)
            }

        }
        .sheet(isPresented: $showingPairing) {
            JARVISCalendarPairingView(nearby: nearby)
        }
        .sheet(isPresented: $presentingNew) {
            JARVISCalendarEditor(store: store, selectedDate: selectedDate) { saved in
                selectedDate = saved.startAt
                displayedMonth = saved.startAt
                statusText = "실제 저장 완료 · \(saved.title)"
            }
        }
        .sheet(item: $editing) { event in
            JARVISCalendarEditor(store: store, existing: event, selectedDate: event.startAt) { saved in
                selectedDate = saved.startAt
                displayedMonth = saved.startAt
                statusText = "실제 변경 사항 저장 완료"
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 31, height: 32)
            }
            .accessibilityLabel("이전 달")
            Spacer()
            Text(displayedMonth.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "ko_KR"))))
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button("오늘") {
                selectedDate = Date()
                displayedMonth = Date()
            }
            .font(.system(size: 10))
            .padding(.trailing, 8)
            .foregroundStyle(JARVISPalette.gold)
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 31, height: 32)
            }
            .accessibilityLabel("다음 달")
        }
        .foregroundStyle(JARVISPalette.white)
    }

    private var monthCells: [Date?] {
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
            ?? calendar.startOfDay(for: displayedMonth)
        let days = calendar.range(of: .day, in: .month, for: month) ?? 1..<29
        let offset = (calendar.component(.weekday, from: month) + 5) % 7
        return Array(repeating: nil, count: offset) +
            days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
                .map(Optional.some)
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(date)
        let count = store.events(on: date).count
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 13, weight: selected || today ? .semibold : .regular))
                Circle()
                    .fill(count > 0 ? JARVISPalette.gold : .clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(selected ? JARVISPalette.black : JARVISPalette.white)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(selected ? JARVISPalette.gold : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(today && !selected ? JARVISPalette.gold.opacity(0.6) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), 일정 \(count)건")
    }

    private func shiftMonth(_ offset: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = shifted
        if let first = calendar.date(from: calendar.dateComponents([.year, .month], from: shifted)) {
            selectedDate = first
        }
    }
}

struct JARVISCalendarEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: JARVISCalendarStore

    private let existing: JARVISCalendarRecord?
    private let recognizedDescription: String?
    private let onSaved: (JARVISCalendarRecord) -> Void

    @State private var title: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var endUnknown: Bool
    @State private var location: String
    @State private var notes: String
    @State private var reminder: Int
    @State private var errorText = ""
    @State private var confirmDeletion = false

    init(store: JARVISCalendarStore,
         existing: JARVISCalendarRecord? = nil,
         proposal: JARVISCalendarDraft? = nil,
         selectedDate: Date = Date(),
         onSaved: @escaping (JARVISCalendarRecord) -> Void = { _ in }) {
        self.store = store
        self.existing = existing
        self.recognizedDescription = proposal?.evidence
        self.onSaved = onSaved
        let initial = existing?.startAt ?? proposal?.startAt ??
            Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        _title = State(initialValue: existing?.title ?? proposal?.title ?? "")
        _startAt = State(initialValue: initial)
        _endAt = State(initialValue: existing?.endAt ?? proposal?.endAt ??
            Calendar.current.date(byAdding: .hour, value: 1, to: initial) ?? initial)
        _endUnknown = State(initialValue: existing?.endAt == nil && proposal?.endAt == nil)
        _location = State(initialValue: existing?.location ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
        _reminder = State(initialValue: existing?.reminderMinutes ?? -1)
    }

    private var candidate: JARVISCalendarRecord {
        JARVISCalendarRecord(id: existing?.id ?? UUID(),
                             title: title, startAt: startAt, endAt: endUnknown ? nil : endAt,
                             location: location, notes: notes,
                             reminderMinutes: reminder < 0 ? nil : reminder,
                             createdAt: existing?.createdAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                if let recognizedDescription {
                    Section {
                        Label("이디스가 이해한 일정: \(recognizedDescription)",
                              systemImage: "waveform")
                            .foregroundStyle(JARVISPalette.gold)
                        Text("음성 명령은 초안만 작성합니다. 아래 내용을 확인하고 '저장'을 누르기 전에는 일정이 추가되지 않습니다.")
                            .font(.footnote)
                    }
                }
                Section("일정") {
                    TextField("예: 군산 미팅", text: $title)
                        .accessibilityLabel("일정 제목")
                    DatePicker("시작", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                    Toggle("종료시간 미정", isOn: $endUnknown)
                        .tint(JARVISPalette.gold)
                    if !endUnknown {
                        DatePicker("종료", selection: $endAt, displayedComponents: [.date, .hourAndMinute])
                    }
                    TextField("장소 (선택)", text: $location)
                    TextField("메모 (선택)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("알림") {
                    Picker("일정 알림", selection: $reminder) {
                        Text("안 함").tag(-1)
                        Text("시작 시").tag(0)
                        Text("10분 전").tag(10)
                        Text("30분 전").tag(30)
                        Text("1시간 전").tag(60)
                    }
                }
                let conflicts = store.conflicts(for: candidate)
                if !conflicts.isEmpty {
                    Section {
                        Label("겹치는 일정이 \(conflicts.count)건 있어요.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        ForEach(conflicts) { conflict in
                            Text("\(conflict.title) · \(conflict.startAt.formatted(date: .omitted, time: .shortened))")
                                .font(.footnote)
                        }
                        Text("저장은 가능하지만 먼저 일정을 확인해 주세요.")
                            .font(.footnote)
                    }
                }
                if !errorText.isEmpty {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
                if existing != nil {
                    Section {
                        Button("일정 삭제", role: .destructive) {
                            confirmDeletion = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(JARVISPalette.black)
            .navigationTitle(existing == nil ? "새 일정" : "일정 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(JARVISPalette.gold)
                }
            }
            .alert("일정을 삭제할까요?", isPresented: $confirmDeletion) {
                Button("삭제", role: .destructive) { delete() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("이 일정은 이디스 캘린더에서 삭제됩니다.")
            }
            .preferredColorScheme(.dark)
        }
    }

    private func save() {
        do {
            let record = try store.save(candidate)
            onSaved(record)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete() {
        guard let existing else { return }
        do {
            try store.delete(existing.id)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
