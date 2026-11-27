import SwiftUI

/// JARVIS Alarm: native system alarms, visually consistent with the core.
struct JARVISAlarmView: View {
    @ObservedObject var store: JARVISAlarmStore

    @State private var editing: JARVISAlarmRecord?
    @State private var adding = false
    @State private var testTime: Date?
    @State private var deleting: JARVISAlarmRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("알람")
                    .font(.system(size: 29, weight: .semibold))
                    .tracking(-1)
                Spacer()
                Button {
                    testTime = nil
                    adding = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(JARVISPalette.black)
                        .frame(width: 43, height: 43)
                        .background(JARVISPalette.gold, in: Circle())
                }
                .accessibilityLabel("새 이디스 알람")
            }
            .padding(.top, 22)

            if !store.alarmSupported {
                Label("이 iPhone에서는 iOS 26 이상이 필요해요.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13))
            } else if store.sorted.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "alarm")
                        .font(.system(size: 39, weight: .ultraLight))
                        .foregroundStyle(JARVISPalette.gold)
                    Text("첫 알람을 설정해 보세요.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(JARVISPalette.white)
                    Text("이디스가 정해진 시각에 깨워줄 거예요.")
                        .font(.system(size: 12))
                        .foregroundStyle(JARVISPalette.muted)
                    Button {
                        testTime = Date().addingTimeInterval(3 * 60)
                        adding = true
                    } label: {
                        Label("3분 뒤 시험 알람", systemImage: "clock.badge.checkmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(JARVISPalette.gold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 39)
                .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 10) {
                    ForEach(store.sorted) { alarm in
                        HStack(alignment: .center, spacing: 8) {
                            Button {
                                editing = alarm
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(alarm.timeLabel)
                                        .font(.system(size: 28, weight: .medium, design: .rounded))
                                        .tracking(-0.8)
                                        .foregroundStyle(alarm.isEnabled ? JARVISPalette.white :
                                            JARVISPalette.muted)
                                    Text(alarm.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(alarm.isEnabled ?
                                            JARVISPalette.white.opacity(0.88) : JARVISPalette.muted)
                                        .lineLimit(1)
                                    Text(alarm.recurrenceLabel)
                                        .font(.system(size: 11))
                                        .foregroundStyle(JARVISPalette.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Toggle(alarm.title, isOn: Binding(
                                get: { alarm.isEnabled },
                                set: { enabled in
                                    Task {
                                        _ = await store.setEnabled(alarm.id, to: enabled)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(JARVISPalette.gold)
                            .disabled(store.saving)
                            .accessibilityLabel("\(alarm.title) 알람 켜기 또는 끄기")
                        }
                        .padding(17)
                        .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(JARVISPalette.panelEdge, lineWidth: 0.8))
                        .contextMenu {
                            Button("편집", systemImage: "pencil") { editing = alarm }
                            Button("삭제", systemImage: "trash", role: .destructive) {
                                deleting = alarm
                            }
                        }
                    }
                    HStack {
                        Spacer()
                        Button {
                            testTime = Date().addingTimeInterval(3 * 60)
                            adding = true
                        } label: {
                            Label("3분 뒤 시험", systemImage: "clock")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(JARVISPalette.gold)
                    }
                }
            }

            if store.saving {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("iPhone 시스템에 알람을 등록하고 있어요.")
                }
                .font(.system(size: 11))
                .foregroundStyle(JARVISPalette.muted)
            }
            if let error = store.readError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            if !store.status.isEmpty {
                Text(store.status)
                    .font(.system(size: 11))
                    .foregroundStyle(JARVISPalette.gold)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !store.permissionStatus.isEmpty {
                Text(store.permissionStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(JARVISPalette.muted)
            }

            if !store.sorted.isEmpty {
                Text("알람은 iPhone 시스템이 울립니다. '애기의 아침인사'는 다음 단계에서 연결합니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(JARVISPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .onAppear { store.refresh() }
        .sheet(isPresented: $adding) {
            JARVISAlarmEditor(store: store, proposedTime: testTime)
        }
        .sheet(item: $editing) { alarm in
            JARVISAlarmEditor(store: store, current: alarm, onDelete: {
                editing = nil
                deleting = alarm
            })
        }
        .alert("알람을 삭제할까요?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        )) {
            Button("삭제", role: .destructive) {
                guard let toDelete = deleting else { return }
                Task { _ = await store.delete(toDelete.id) }
                deleting = nil
            }
            Button("취소", role: .cancel) { deleting = nil }
        } message: {
            Text("EIDIS 알람과 iPhone에 예약된 해당 알람이 함께 삭제됩니다.")
        }
    }
}

struct JARVISAlarmEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: JARVISAlarmStore

    private let current: JARVISAlarmRecord?
    private let onDelete: (() -> Void)?

    @State private var time: Date
    @State private var title: String
    @State private var repeatDays: Set<Int>
    @State private var isRepeating: Bool
    @State private var feedback = ""

    private let weekdays: [(id: Int, label: String)] = [
        (2, "월"), (3, "화"), (4, "수"), (5, "목"),
        (6, "금"), (7, "토"), (1, "일")
    ]

    init(store: JARVISAlarmStore,
         current: JARVISAlarmRecord? = nil,
         proposedTime: Date? = nil,
         onDelete: (() -> Void)? = nil) {
        self.store = store
        self.current = current
        self.onDelete = onDelete
        let initial = proposedTime ??
            Calendar.current.date(bySettingHour: current?.hour ?? 7,
                                  minute: current?.minute ?? 0,
                                  second: 0, of: Date()) ?? Date()
        _time = State(initialValue: initial)
        _title = State(initialValue: current?.title ?? "좋은 아침이에요, DECHIVE")
        _repeatDays = State(initialValue: Set(current?.weekdays ?? []))
        _isRepeating = State(initialValue: !(current?.weekdays.isEmpty ?? true))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("알람 시간", selection: $time,
                               displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                Section("이름") {
                    TextField("예: 기상 알람", text: $title)
                        .accessibilityIdentifier("jarvis-alarm-title")
                }
                Section("반복") {
                    Toggle("요일 반복", isOn: $isRepeating)
                        .tint(JARVISPalette.gold)
                    if isRepeating {
                        HStack(spacing: 5) {
                            ForEach(weekdays, id: \.id) { day in
                                Button {
                                    if repeatDays.contains(day.id) {
                                        repeatDays.remove(day.id)
                                    } else {
                                        repeatDays.insert(day.id)
                                    }
                                } label: {
                                    Text(day.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(repeatDays.contains(day.id)
                                            ? JARVISPalette.black : JARVISPalette.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 38)
                                        .background(
                                            repeatDays.contains(day.id)
                                                ? JARVISPalette.gold : JARVISPalette.panel,
                                            in: Circle()
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(day.label)요일")
                                .accessibilityAddTraits(repeatDays.contains(day.id)
                                    ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 8)
                        Button("평일") { repeatDays = Set(2...6) }
                        Button("매일") { repeatDays = Set(1...7) }
                    } else {
                        Text("가장 가까운 다음 시각에 한 번만 울립니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if !feedback.isEmpty {
                    Section {
                        Text(feedback)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                if current != nil, let onDelete {
                    Section {
                        Button("알람 삭제", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                    }
                }
                Section {
                    Text("실제로 알람이 등록될 때만 저장 완료로 표시됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(JARVISPalette.black)
            .navigationTitle(current == nil ? "새 알람" : "알람 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        Task { await commit() }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(JARVISPalette.gold)
                    .disabled(store.saving)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func commit() async {
        let hour = Calendar.current.component(.hour, from: time)
        let minute = Calendar.current.component(.minute, from: time)
        if isRepeating && repeatDays.isEmpty {
            feedback = "반복할 요일을 하나 이상 선택해 주세요."
            return
        }
        var record = current ?? JARVISAlarmRecord()
        record.hour = hour
        record.minute = minute
        record.title = title
        record.weekdays = isRepeating ? repeatDays.sorted() : []
        record.isEnabled = true
        let okay = await store.save(record)
        if okay { dismiss() }
        else { feedback = store.status }
    }
}
