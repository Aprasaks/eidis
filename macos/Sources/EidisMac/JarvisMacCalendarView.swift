import SwiftUI

/// Native JARVIS Calendar surface for the Mac overlay and standalone window.
/// Only a confirmed localhost DB response counts as a saved event.
struct JarvisMacCalendarView: View {
    @ObservedObject var model: JarvisMacCalendarStore
    @ObservedObject private var nearby = JarvisMacNearbyCalendar.shared
    let onClose: (() -> Void)?

    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()
    @State private var editing: JarvisMacCalendarEvent?
    @State private var editorOpen = false
    @State private var eventTitle = ""
    @State private var eventPlace = ""
    @State private var eventDescription = ""
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var endUnknown = true
    @State private var confirmDelete = false
    @State private var formWarning = ""

    private var shown: [JarvisMacCalendarEvent] {
        model.entries.filter { event in
            guard let start = event.startDate else { return false }
            return Calendar.current.isDate(start, inSameDayAs: selectedDate)
        }
    }

    private var combinedStart: Date? {
        Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: startTime),
                              minute: Calendar.current.component(.minute, from: startTime),
                              second: 0, of: selectedDate)
    }

    private var combinedEnd: Date? {
        if endUnknown { return nil }
        return Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: endTime),
                                     minute: Calendar.current.component(.minute, from: endTime),
                                     second: 0, of: selectedDate)
    }

    private var conflictEvents: [JarvisMacCalendarEvent] {
        guard let start = combinedStart else { return [] }
        let end = combinedEnd
        return model.entries.filter { other in
            guard other.id != editing?.id,
                  Calendar.current.isDate(other.startDate ?? .distantPast, inSameDayAs: selectedDate),
                  let otherStart = other.startDate else { return false }
            // Unknown end times are NOT secretly treated as one hour.
            // We can only compare definitely overlapping intervals.
            if let end, let otherEnd = other.endDate {
                return start < otherEnd && end > otherStart
            }
            return start == otherStart
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("EIDIS / CALENDAR")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(.orange)
                    Text("일정 관리")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: { Label("새로고침", systemImage: "arrow.clockwise") }
                    .disabled(model.loading || model.saving)
                Button {
                    nearby.remembered || nearby.connected ? nearby.disconnect() : nearby.startPairing()
                } label: {
                    Label(nearby.remembered || nearby.connected ? "기기 등록 해제" : "iPhone 연결",
                          systemImage: "iphone.gen3.radiowaves.left.and.right")
                }
                .tint(.orange)
                Button {
                    beginNew()
                } label: { Label("새 일정", systemImage: "plus") }
                    .tint(.orange)
                    .keyboardShortcut("n", modifiers: [.command])
                if let onClose {
                    Button(action: onClose) {
                        Label("닫기", systemImage: "xmark")
                    }
                }
            }
            .font(.system(size: 12))

            if nearby.isAdvertising || nearby.connected || nearby.remembered {
                HStack(spacing: 10) {
                    Image(systemName: nearby.connected ? "checkmark.circle.fill" : "lock.iphone")
                        .foregroundStyle(.orange)
                    if nearby.connected {
                        Text("iPhone 연결됨")
                            .font(.system(size: 12, weight: .medium))
                    } else if nearby.remembered {
                        Text("등록된 iPhone 대기")
                    } else {
                        Text("연결 코드")
                            .font(.system(size: 12))
                        Text(nearby.code)
                            .font(.system(size: 19, weight: .bold, design: .monospaced))
                            .tracking(3)
                    }
                    Spacer()
                    Text(nearby.status)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(.orange.opacity(0.085),
                            in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    monthGrid

                    HStack {
                        Text(selectedDate.formatted(.dateTime.year().month().day().weekday(.wide)
                            .locale(Locale(identifier: "ko_KR"))))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(shown.count)건")
                            .foregroundStyle(.orange)
                    }
                    .font(.system(size: 12))

                    if shown.isEmpty {
                        VStack(spacing: 9) {
                            Image(systemName: "calendar")
                                .font(.system(size: 24, weight: .ultraLight))
                                .foregroundStyle(.orange.opacity(0.65))
                            Text("이 날짜에 기록된 일정이 없습니다.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.7))
                            Button("이날 일정 만들기") { beginNew() }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(.white.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 8) {
                                ForEach(shown) { event in
                                    Button {
                                        beginEdit(event)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack {
                                                Text(event.title)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.orange)
                                            }
                                            Text((event.startDate?.formatted(date: .omitted, time: .shortened) ?? "시작 시각 확인 필요")
                                                + " – " + (event.endDate?.formatted(date: .omitted, time: .shortened) ?? "종료 미정"))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.58))
                                            if !event.location.isEmpty {
                                                Label(event.location, systemImage: "mappin")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.white.opacity(0.7))
                                            }
                                        }
                                        .padding(13)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.white.opacity(0.065),
                                                    in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("jarvis-calendar-event-\(event.id)")
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(minWidth: 275, maxWidth: 330)

                VStack(alignment: .leading, spacing: 14) {
                    if editorOpen {
                        editor
                    } else {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("일정 상세")
                                .font(.system(size: 18, weight: .medium))
                            Text("왼쪽에서 날짜나 일정을 선택하거나, 새 일정을 등록할 수 있습니다.")
                                .foregroundStyle(.white.opacity(0.65))
                                .font(.system(size: 13))
                            Button("일정 작성하기") { beginNew() }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(21)
                        .background(.white.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                if model.loading || model.saving {
                    ProgressView().controlSize(.small).tint(.orange)
                }
                Text(model.status)
                    .font(.system(size: 11))
                    .foregroundStyle(model.lastLoadedAt == nil ? .orange : .white.opacity(0.7))
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let date = model.lastLoadedAt {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.47))
                }
            }
        }
        .padding(18)
        .background(Color(red: 0.034, green: 0.035, blue: 0.042))
        .overlay(RoundedRectangle(cornerRadius: 15)
            .stroke(.orange.opacity(0.30), lineWidth: 1))
        .foregroundStyle(.white)
        .onAppear {
            if model.presentingNew {
                beginNew(fromVoice: true)
            }
            Task { await model.refresh() }
        }
        .onChange(of: model.presentingNew) { _, next in
            if next { beginNew(fromVoice: true) }
        }
        .onChange(of: selectedDate) { _, day in
            if !Calendar.current.isDate(day, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = day
            }
        }
        .confirmationDialog("이 일정을 삭제할까요?", isPresented: $confirmDelete) {
            Button("일정 삭제", role: .destructive) { Task { await remove() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이디스 캘린더에서 삭제합니다. 다른 앱의 일정은 건드리지 않습니다.")
        }
        .accessibilityIdentifier("jarvis-calendar-panel")
    }

    private var monthGrid: some View {
        let calendar = Calendar.current
        let mondayFirst = ["월", "화", "수", "목", "금", "토", "일"]
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("이전 달")
                Spacer()
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)
                    .locale(Locale(identifier: "ko_KR"))))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("오늘") {
                    selectedDate = Date()
                    displayedMonth = selectedDate
                }
                .font(.system(size: 11))
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("다음 달")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .padding(.vertical, 6)

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(mondayFirst, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(monthDates.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let chosen = calendar.isDate(day, inSameDayAs: selectedDate)
                        let today = calendar.isDateInToday(day)
                        let scheduled = !model.entries.filter {
                            if let start = $0.startDate { return calendar.isDate(start, inSameDayAs: day) }
                            return false
                        }.isEmpty
                        Button {
                            selectedDate = day
                            if editorOpen && editing == nil {
                                formWarning = "날짜를 바꿨어요. 시작시간도 확인해 주세요."
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(calendar.component(.day, from: day))")
                                    .font(.system(size: 12, weight: chosen || today ? .semibold : .regular))
                                Circle()
                                    .fill(scheduled ? (chosen ? Color.black : Color.orange) : .clear)
                                    .frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 35)
                            .foregroundStyle(chosen ? .black : .white.opacity(0.80))
                            .background(chosen ? Color.orange : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .stroke(today && !chosen ? .orange.opacity(0.80) : .clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(scheduled ? "등록된 일정 있음" : "등록된 일정 없음")")
                    } else {
                        Color.clear.frame(height: 35)
                    }
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(.white.opacity(0.075), lineWidth: 0.8))
    }

    private var monthDates: [Date?] {
        let calendar = Calendar.current
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
            ?? calendar.startOfDay(for: displayedMonth)
        let offset = (calendar.component(.weekday, from: first) + 5) % 7
        let days = calendar.range(of: .day, in: .month, for: first) ?? 1..<29
        return Array(repeating: Optional<Date>.none, count: offset) +
            days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
                .map(Optional.some)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = next
        if let first = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: next)) {
            selectedDate = first
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(editing == nil ? "새 일정 등록" : "일정 수정")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button("취소") { editorOpen = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.56))
                }

                fieldLabel("날짜")
                DatePicker("날짜", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.field)
                    .labelsHidden()

                fieldLabel("시작시간")
                DatePicker("시작시간", selection: $startTime, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.field)
                    .labelsHidden()

                Toggle("종료시간 미정", isOn: $endUnknown)
                    .tint(.orange)
                    .font(.system(size: 12))
                    .accessibilityIdentifier("jarvis-calendar-end-unknown")
                if !endUnknown {
                    fieldLabel("종료시간")
                    DatePicker("종료시간", selection: $endTime, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.field)
                        .labelsHidden()
                }

                fieldLabel("제목")
                TextField("어떤 일정인가요?", text: $eventTitle)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("jarvis-calendar-title")

                fieldLabel("장소")
                TextField("장소를 입력하세요 (선택)", text: $eventPlace)
                    .textFieldStyle(.roundedBorder)

                fieldLabel("상세내용")
                TextEditor(text: $eventDescription)
                    .frame(minHeight: 90)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.white.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("jarvis-calendar-description")

                if !conflictEvents.isEmpty {
                    Label("겹치는 일정이 \(conflictEvents.count)건 있습니다. 저장 전 확인해 주세요.",
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                if !formWarning.isEmpty {
                    Text(formWarning)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button {
                        Task { await save() }
                    } label: {
                        Label(editing == nil ? "일정 저장" : "변경 내용 저장",
                              systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(model.saving || eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityIdentifier("jarvis-calendar-save")

                    Spacer()

                    if editing != nil {
                        Button("삭제", role: .destructive) {
                            confirmDelete = true
                        }
                        .disabled(model.saving)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))
    }

    private func beginNew(fromVoice: Bool = false) {
        editing = nil
        editorOpen = true
        formWarning = ""
        eventTitle = fromVoice ? model.draftTitle : ""
        if fromVoice {
            selectedDate = model.draftStart
            displayedMonth = model.draftStart
            startTime = model.draftStart
        } else {
            startTime = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0,
                                              of: selectedDate) ?? selectedDate
        }
        endTime = Calendar.current.date(byAdding: .hour, value: 1, to: startTime) ?? startTime
        endUnknown = true
        eventPlace = ""
        eventDescription = ""
        model.presentingNew = false
    }

    private func beginEdit(_ event: JarvisMacCalendarEvent) {
        guard let start = event.startDate else { return }
        editing = event
        editorOpen = true
        formWarning = ""
        selectedDate = start
        displayedMonth = start
        startTime = start
        endUnknown = event.endAt == nil
        endTime = event.endDate ?? start
        eventTitle = event.title
        eventPlace = event.location
        eventDescription = event.notes
    }

    private func save() async {
        guard let start = combinedStart else {
            formWarning = "시작시간이 유효하지 않아요."
            return
        }
        let end = combinedEnd
        if !endUnknown, end == nil {
            formWarning = "종료시간이 유효하지 않아요."
            return
        }
        if let end, end <= start {
            formWarning = "종료시간은 시작시간보다 늦어야 합니다. 모르면 '미정'을 선택하세요."
            return
        }
        formWarning = ""
        let ok: Bool
        if let existing = editing {
            ok = await model.update(existing, title: eventTitle, start: start, end: end,
                                    location: eventPlace, detail: eventDescription)
        } else {
            ok = await model.create(title: eventTitle, start: start, end: end,
                                    location: eventPlace, detail: eventDescription)
        }
        if ok { editorOpen = false }
        else { formWarning = model.status }
    }

    private func remove() async {
        guard let existing = editing else { return }
        let ok = await model.delete(existing)
        if ok { editing = nil; editorOpen = false }
        else { formWarning = model.status }
    }
}
