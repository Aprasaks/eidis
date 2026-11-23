import SwiftUI

/// Touch and voice both navigate to the same real data surfaces.
/// A view being available never implies that the Mac data is connected.
enum JARVISMobilePage: String, CaseIterable, Identifiable {
    case core, dashboard, alarm, calendar, memory, stocks, projects, knowledge, social, news, system

    var id: String { rawValue }

    /// Simulator visual QA hook. Not used by normal launches or release builds.
    static var initialPageForVerification: Self {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let choice = args.first(where: { $0.hasPrefix("--jarvis-mobile-preview=") }),
           let name = choice.split(separator: "=", maxSplits: 1).last,
           let page = Self(rawValue: String(name)) {
            return page
        }
        if let raw = ProcessInfo.processInfo.environment["JARVIS_MOBILE_PREVIEW_PAGE"],
           let page = Self(rawValue: raw) {
            return page
        }
        #endif
        return .core
    }

    var title: String {
        switch self {
        case .core: "코어"
        case .dashboard: "전체 현황"
        case .calendar: "일정"
        case .alarm: "알람"
        case .memory: "기억"
        case .stocks: "주식"
        case .projects: "프로젝트"
        case .knowledge: "지식 보관함"
        case .social: "SNS"
        case .news: "뉴스"
        case .system: "시스템"
        }
    }

    var icon: String {
        switch self {
        case .core: "circle.hexagongrid"
        case .dashboard: "square.grid.2x2"
        case .calendar: "calendar"
        case .alarm: "alarm"
        case .memory: "brain.head.profile"
        case .stocks: "chart.xyaxis.line"
        case .projects: "folder"
        case .knowledge: "archivebox"
        case .social: "person.2"
        case .news: "newspaper"
        case .system: "desktopcomputer"
        }
    }

    var summary: String {
        switch self {
        case .core: "금빛 코어와 대화"
        case .dashboard: "전체 정보를 한눈에"
        case .calendar: "JARVIS 자체 일정"
        case .alarm: "자비스 기상 알람"
        case .memory: "자비스가 기억한 정보"
        case .stocks: "국내·미국 주식 현황표"
        case .projects: "프로젝트와 작업 기록"
        case .knowledge: "보관한 지식과 자료"
        case .social: "SNS 채널 정보"
        case .news: "뉴스 및 브리핑"
        case .system: "맥과 자비스 상태"
        }
    }

    var sourceNotice: String {
        switch self {
        case .core: "아이폰 자비스에서 직접 실행"
        case .dashboard: "맥 데이터 연결 준비 중"
        case .calendar: "JARVIS 자체 일정 저장소 · 이 아이폰"
        case .alarm: "JARVIS 자체 알람 · iPhone 시스템"
        case .memory: "맥 자비스의 개인 기억과 프로필 · 연결 전"
        case .stocks: "맥 자비스 증권 데이터 · 연결 전"
        case .projects: "맥 자비스 프로젝트 기록 · 연결 전"
        case .knowledge: "맥 자비스 저장 자료 · 연결 전"
        case .social: "맥 자비스 SNS 연동 · 연결 전"
        case .news: "맥 자비스 뉴스 브리핑 · 연결 전"
        case .system: "맥 자비스 시스템 정보 · 연결 전"
        }
    }

    /// Offline navigation only. This does not call any server or claim that
    /// an action succeeded; it just selects the corresponding view.
    static func requestedPage(for raw: String) -> JARVISMobilePage? {
        let text = raw.lowercased().filter { !$0.isWhitespace && !$0.isNewline && !$0.isPunctuation }
        guard !text.isEmpty else { return nil }
        let action = ["열어", "보여", "띄워", "확인", "알려", "보고", "화면", "현황", "어때", "돌아", "가자", "맞춰", "설정", "깨워"]
            .contains { text.contains($0) }
        guard action else { return nil }

        if ["코어로", "기본화면", "처음화면", "원래화면"].contains(where: text.contains) {
            return .core
        }
        if ["전체대시보드", "전체현황", "종합현황", "통합현황",
            "전체상황", "모든현황", "관제실", "대시보드", "현황판"]
            .contains(where: text.contains) {
            return .dashboard
        }
        if ["알람", "기상", "깨워", "모닝콜"].contains(where: text.contains) {
            return .alarm
        }
        if ["캘린더", "일정", "스케줄", "약속"].contains(where: text.contains) {
            return .calendar
        }
        if ["내기억", "기억", "프로필"].contains(where: text.contains) {
            return .memory
        }
        if ["주식", "증권", "코스피", "나스닥", "종목"].contains(where: text.contains) {
            return .stocks
        }
        if ["프로젝트", "깃허브", "작업현황", "진행중인작업"].contains(where: text.contains) {
            return .projects
        }
        if ["저장자료", "자료실", "보관함", "내지식"].contains(where: text.contains) {
            return .knowledge
        }
        if ["SNS", "sns", "인스타", "스레드", "유튜브", "페이스북"].contains(where: text.contains) {
            return .social
        }
        if ["뉴스", "브리핑"].contains(where: text.contains) {
            return .news
        }
        if ["시스템", "맥북상태", "맥상태", "컴퓨터상태", "연결상태"].contains(where: text.contains) {
            return .system
        }
        return nil
    }

    var spokenStatus: String {
        switch self {
        case .core: return "오라버니, 코어 화면으로 돌아왔어요."
        case .dashboard: return "오라버니, 전체 현황 화면을 열었어요. 맥에서 가져오는 정보는 아직 연결 전이에요."
        case .calendar: return "오라버니, 자비스 캘린더를 열었어요. 저장된 일정과 새 일정을 확인할 수 있어요."
        case .alarm: return "오라버니, 자비스 알람을 열었어요. 원하는 시각을 설정하고 저장해 주세요."
        default: return "오라버니, \(title) 화면을 열었어요. 맥 자비스가 아직 연결되지 않아 실제 데이터는 표시하지 않았어요."
        }
    }
}

struct JARVISMobileDashboardView: View {
    @ObservedObject var calendar: JARVISCalendarStore
    @ObservedObject var nearby: JARVISMobileNearbyCalendar
    let onOpen: (JARVISMobilePage) -> Void

    private let panels: [JARVISMobilePage] = [
        .alarm, .calendar, .memory, .stocks, .projects,
        .knowledge, .social, .news, .system
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            VStack(alignment: .leading, spacing: 9) {
                Text("전체 현황")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-1.2)
            }
            .padding(.top, 25)

            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 11),
                                    GridItem(.flexible(), spacing: 11)], spacing: 11) {
                    ForEach(panels) { panel in
                        Button { onOpen(panel) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: panel.icon)
                                        .font(.system(size: 21, weight: .light))
                                        .foregroundStyle(JARVISPalette.gold)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(JARVISPalette.muted)
                                }
                                Spacer(minLength: 0)
                                Text(panel.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(JARVISPalette.white)
                                Text(panel.summary)
                                    .font(.system(size: 10))
                                    .foregroundStyle(JARVISPalette.muted)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 107, alignment: .leading)
                            .padding(14)
                            .background(JARVISPalette.panel,
                                        in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15)
                                .stroke(JARVISPalette.panelEdge, lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(panel.sourceNotice)
                    }
                }
            }

        }
    }


}

struct JARVISMobileDataPageView: View {
    let page: JARVISMobilePage
    @ObservedObject var calendar: JARVISCalendarStore
    @ObservedObject var nearby: JARVISMobileNearbyCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if page != .calendar {
            HStack {
                Image(systemName: page.icon)
                    .font(.system(size: 25))
                    .foregroundStyle(JARVISPalette.gold)
                Spacer()
            }
            .padding(.top, 29)
            Text(page.title)
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.9)
            }

            if page == .calendar {
                JARVISCalendarView(store: calendar, nearby: nearby)
            } else {
                macDisconnectedBody
            }
            Spacer(minLength: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var macDisconnectedBody: some View {
        VStack(spacing: 14) {
            Image(systemName: page.icon)
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(JARVISPalette.gold)
            Text("연결 준비 중")
                .font(.system(size: 14))
                .foregroundStyle(JARVISPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
