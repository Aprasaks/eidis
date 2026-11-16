import SwiftUI
import UIKit

enum EIDISService: String, Identifiable {
    case weather
    case calendar
    case reminders

    var id: String { rawValue }
    var title: String {
        switch self {
        case .weather: return "현재 날씨"
        case .calendar: return "iPhone 일정"
        case .reminders: return "iPhone 미리 알림"
        }
    }
}

/// The user explicitly opens this screen and chooses to grant permissions.
/// No data is silently copied to Mac, cloud AI or any other server.
struct EIDISServiceSheet: View {
    let service: EIDISService
    @ObservedObject var personal: EIDISPersonalData
    @ObservedObject var weather: EIDISWeatherService

    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 0.008, green: 0.011, blue: 0.018)
    private let panel = Color(red: 0.058, green: 0.069, blue: 0.088)
    private let muted = Color(red: 0.69, green: 0.72, blue: 0.78)
    private let accent = Color(red: 0.31, green: 0.82, blue: 0.91)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    switch service {
                    case .weather: weatherContent
                    case .calendar: calendarContent
                    case .reminders: remindersContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(ink.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle(service.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .tint(accent)
        .preferredColorScheme(.dark)
    }

    private var weatherContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(weather.displayValue)
                .font(.system(size: 30, weight: .semibold))
            if let reading = weather.reading {
                detailRow("체감 기온", "\(Int(reading.feelsLike.rounded()))°C")
                detailRow("습도", "\(reading.humidity)%")
                detailRow("풍속", "\(Int(reading.wind.rounded())) km/h")
                detailRow("제공처", reading.provider)
                detailRow("마지막 조회", reading.fetchedAt.formatted(
                    .dateTime.month().day().hour().minute()
                        .locale(Locale(identifier: "ko_KR"))))
                if !reading.isFresh {
                    Text("오래된 정보입니다. 다시 조회해 주세요.")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            if let message = weather.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                weather.connectOrRefresh()
            } label: {
                Label(weather.reading == nil ? "위치 허용하고 날씨 조회" : "날씨 새로고침",
                      systemImage: "location.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(weather.busy)

            if weather.busy { ProgressView("날씨를 불러오는 중") }
            Text("선택한 순간에만 iPhone의 위치를 확인하고, 위치 좌표를 Open-Meteo에 보내고, 연결이 실패하면 wttr.in에 보내 날씨를 조회합니다. 계정이나 대화 내용은 보내지 않습니다.")
                .font(.caption)
                .foregroundStyle(muted)
            Text("출처: Open-Meteo (CC BY 4.0) / 보조 wttr.in · 개인 용도")
                .font(.system(size: 11))
                .foregroundStyle(muted)
        }
    }

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(personal.calendarStatus)
                .font(.headline)
                .foregroundStyle(personal.calendarConnected ? .white : muted)
            Button {
                Task { await personal.connectCalendar() }
            } label: {
                Label(personal.calendarConnected ? "앞으로 7일 일정 새로고침" : "캘린더 연결",
                      systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(personal.calendarBusy)
            if personal.calendarBusy { ProgressView("캘린더 확인 중") }
            if personal.calendarConnected, personal.calendarLoaded {
                Text("앞으로 7일 · \(personal.events.count)개")
                    .font(.caption)
                    .foregroundStyle(muted)
                if personal.events.isEmpty {
                    detailRow("예정된 일정", "없음")
                } else {
                    ForEach(personal.events) { event in
                        detailRow(event.timeLabel, event.title)
                    }
                }
            }
            Text("Apple 캘린더에서 다음 7일 일정을 읽어옵니다. 읽기 권한을 위해 iOS에서 '전체 접근' 승인이 필요하지만, EIDIS는 일정을 생성·수정·삭제하지 않습니다.")
                .font(.caption)
                .foregroundStyle(muted)
            settingsLink
        }
    }

    private var remindersContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(personal.remindersStatus)
                .font(.headline)
                .foregroundStyle(personal.remindersConnected ? .white : muted)
            Button {
                Task { await personal.connectReminders() }
            } label: {
                Label(personal.remindersConnected ? "미리 알림 새로고침" : "미리 알림 연결",
                      systemImage: "checkmark.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(personal.remindersBusy)
            if personal.remindersBusy { ProgressView("미리 알림 확인 중") }
            if personal.remindersConnected, personal.remindersLoaded {
                Text("미완료 · \(personal.tasks.count)개")
                    .font(.caption)
                    .foregroundStyle(muted)
                if personal.tasks.isEmpty {
                    detailRow("미완료 항목", "없음")
                } else {
                    ForEach(personal.tasks) { item in
                        detailRow(item.dueLabel, item.title)
                    }
                }
            }
            Text("iPhone Apple 미리 알림에서 완료하지 않은 할 일을 읽어옵니다. Apple이 요구하는 전체 접근 권한을 받지만, EIDIS는 항목을 생성·완료·삭제하지 않습니다. Mac 자비스의 프로젝트 작업과는 별개입니다.")
                .font(.caption)
                .foregroundStyle(muted)
            settingsLink
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(muted)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(panel, in: RoundedRectangle(cornerRadius: 13))
    }

    private var settingsLink: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } label: {
            Label("권한이 거절된 경우 iPhone 설정 열기", systemImage: "gearshape")
                .font(.caption)
        }
    }
}
