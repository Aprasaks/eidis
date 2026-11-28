import SwiftUI

/// Touch and voice both navigate to the same real data surfaces.
/// A view being available never implies that the Mac data is connected.
enum JARVISMobilePage: String, CaseIterable, Identifiable {
    case core, dashboard, alarm, calendar, approval, memory, stocks, projects, knowledge, social, news, system

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
        case .approval: "승인"
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
        case .approval: "checkmark.seal"
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
        case .calendar: "EIDIS 자체 일정"
        case .alarm: "이디스 기상 알람"
        case .approval: "승인 기다리는 게시물"
        case .memory: "기획서와 주식"
        case .stocks: "국내·미국 주식 현황표"
        case .projects: "프로젝트와 작업 기록"
        case .knowledge: "보관한 지식과 자료"
        case .social: "SNS 채널 정보"
        case .news: "뉴스 및 브리핑"
        case .system: "맥과 이디스 상태"
        }
    }

    var sourceNotice: String {
        switch self {
        case .core: "아이폰 이디스에서 직접 실행"
        case .dashboard: "맥 데이터 연결 준비 중"
        case .calendar: "EIDIS 자체 일정 저장소 · 이 아이폰"
        case .alarm: "EIDIS 자체 알람 · iPhone 시스템"
        case .approval: "SNS 캐러셀 · 지식 글 승인"
        case .memory: "맥 이디스 기획서 · 주식"
        case .stocks: "맥 이디스 증권 데이터 · 연결 전"
        case .projects: "공개 지식 현황 및 연결된 Mac 작업 기록"
        case .knowledge: "맥 이디스 저장 자료 · 연결 전"
        case .social: "캐러셀 검토·승인 · 채널 현황"
        case .news: "맥 이디스 뉴스 브리핑 · 연결 전"
        case .system: "맥 이디스 시스템 정보 · 연결 전"
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
        if ["승인", "검토할", "결재"].contains(where: text.contains) {
            return .approval
        }
        if ["내기억", "기억", "프로필", "기획서"].contains(where: text.contains) {
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
        case .core: return "DECHIVE, 코어 화면으로 돌아왔어요."
        case .dashboard: return "DECHIVE, 전체 현황 화면을 열었어요. 맥에서 가져오는 정보는 아직 연결 전이에요."
        case .projects: return "DECHIVE, 프로젝트 화면을 열었어요. 확인 가능한 기록을 불러올게요."
        case .calendar: return "DECHIVE, 이디스 캘린더를 열었어요. 저장된 일정과 새 일정을 확인할 수 있어요."
        case .alarm: return "DECHIVE, 이디스 알람을 열었어요. 원하는 시각을 설정하고 저장해 주세요."
        case .approval: return "DECHIVE, 승인 화면을 열었어요. 맥 이디스가 만든 게시물을 확인할게요."
        case .social: return "DECHIVE, SNS 화면을 열었어요. 맥 이디스가 만든 캐러셀을 확인할게요."
        default: return "DECHIVE, \(title) 화면을 열었어요. 맥 이디스가 아직 연결되지 않아 실제 데이터는 표시하지 않았어요."
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
            } else if page == .projects {
                JARVISMobileProjectsView(nearby: nearby)
            } else if page == .approval {
                // 승인함 (P7 M2): SNS 캐러셀과 dechive.dev 지식 글을 한 탭에서 승인한다
                JARVISApprovalInboxView(nearby: nearby)
            } else if page == .social {
                // SNS: Mac 자비스 캐러셀 미리보기·승인 (JARVISMobileSocialView.swift)
                JARVISMobileSocialView(nearby: nearby)
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


/// 승인 탭 (기획서 P7 M2): 승인이 필요한 것을 한곳에.
/// - SNS: 이디스가 만든 캐러셀 미리보기 → 승인하면 22:00 인스타 · 09:00 Threads 자동 게시
/// - 지식 글: 밤 작업이 만든 dechive.dev 원고 → 목차 순서대로 확인 후 발행
struct JARVISApprovalInboxView: View {
    enum Section: String, CaseIterable, Identifiable {
        case social = "SNS", knowledge = "지식 글", memory = "기억 후보"
        var id: String { rawValue }
    }
    @ObservedObject var nearby: JARVISMobileNearbyCalendar
    @State private var section: Section = .social

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("승인 항목", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch section {
            case .social:
                pauseSwitch
                JARVISMobileSocialView(nearby: nearby)
            case .knowledge: JARVISMobileProjectsView(nearby: nearby)
            case .memory: memoryCandidates
            }
        }
        .onAppear { nearby.refreshSNSPause() }
    }

    /// P6 A1 긴급 정지: 인스타·Threads 자동 게시를 한 번에 멈춘다 (맥 SNS 방과 같은 스위치)
    private var pauseSwitch: some View {
        Toggle(isOn: Binding(get: { nearby.snsPaused ?? false },
                             set: { nearby.refreshSNSPause(set: $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("자동 게시 멈춤").font(.subheadline.weight(.semibold))
                Text(nearby.snsPaused == true ? "멈춤 · 인스타·Threads 자동 게시 안 함" : "켜짐 · 승인된 글은 정해진 시간에 게시")
                    .font(.caption).foregroundStyle(JARVISPalette.muted)
            }
        }
        .tint(.red)
        .disabled(nearby.snsPaused == nil)
        .padding(14)
        .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 13))
    }

    /// P7 M3: 밤에 폰 대화에서 뽑은 기억 후보. 승인한 것만 이디스가 기억한다.
    private var memoryCandidates: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(nearby.learningStatus).font(.caption).foregroundStyle(JARVISPalette.muted)
                Spacer()
                Button { nearby.refreshLearning() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(nearby.learningBusy)
                    .accessibilityLabel("기억 후보 새로고침")
            }
            // P3 S5: 이디스가 알아들은 새 표현 → 예문으로 추가하면 다음부터 바로 알아듣는다
            if !nearby.routeProposals.isEmpty {
                Text("명령 예문 제안").font(.subheadline.weight(.semibold)).foregroundStyle(JARVISPalette.gold)
                ForEach(nearby.routeProposals) { route in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("“" + route.phrase + "”").font(.subheadline)
                            Text("→ " + route.skill + " · " + route.action).font(.caption).foregroundStyle(JARVISPalette.muted)
                        }
                        Spacer()
                        Button("추가") { nearby.refreshLearning(action: "approveRoute", id: route.id) }
                            .buttonStyle(.borderedProminent).tint(JARVISPalette.gold).foregroundStyle(JARVISPalette.black)
                        Button { nearby.refreshLearning(action: "rejectRoute", id: route.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.bordered)
                    }
                    .disabled(nearby.learningBusy)
                    .padding(12)
                    .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 13))
                }
                Text("기억 후보").font(.subheadline.weight(.semibold)).foregroundStyle(JARVISPalette.gold).padding(.top, 6)
            }
            ForEach(nearby.learningPending) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.content).font(.subheadline.weight(.semibold))
                    if !item.source.isEmpty {
                        Text("“" + item.source + "”").font(.caption).foregroundStyle(JARVISPalette.muted).lineLimit(3)
                    }
                    HStack {
                        Button("기억하기") { nearby.refreshLearning(action: "approve", id: item.id) }
                            .buttonStyle(.borderedProminent).tint(JARVISPalette.gold)
                            .foregroundStyle(JARVISPalette.black)
                        Button("버리기") { nearby.refreshLearning(action: "reject", id: item.id) }
                            .buttonStyle(.bordered)
                    }
                    .disabled(nearby.learningBusy)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 13))
            }
        }
        .onAppear { nearby.refreshLearning() }
    }
}

struct JARVISLearningCandidate: Decodable, Identifiable {
    let id: Int
    let category: String
    let content: String
    let source: String
}

struct JARVISRouteProposal: Decodable, Identifiable {
    let id: Int
    let phrase: String
    let skill: String
    let action: String
}

struct JARVISLearningReply: Decodable {
    let pending: [JARVISLearningCandidate]
    let approvedCount: Int
    let routes: [JARVISRouteProposal]?
}

/// Project metadata and owner-only staged article previews.
struct JARVISProjectSnapshot: Decodable {
    let checkedAt: String
    let day: String
    let planned: Int?
    let starts: Int
    let limit: Int
    let dailyStagedCount: Int?
    let repairStarts: Int?
    let repairLimit: Int?
    let nightReason: String?
    let nightStaged: String?
    let latestTitle: String?
    let latestCode: String?
    let latestState: String?
    let reviewRecorded: Bool?
    let reviews: [JARVISReviewArticle]?
}

struct JARVISReviewArticle: Decodable, Identifiable {
    let slug: String
    let rev: String
    let title: String
    let article: String
    let assets: [String: String]
    let checkedAt: String
    let topicNumber: Int?
    let topicCode: String?
    var id: String { slug + ":" + rev }
    var numberedTitle: String {
        guard let topicNumber else { return title }
        return String(format: "%03d", topicNumber) + " · " + title
    }

    func imageURL(_ name: String) -> URL? {
        guard let ref = assets[name],
              ref.range(of: "^image-[a-f0-9]+-[0-9]+x[0-9]+-png$", options: .regularExpression) != nil else { return nil }
        let file = String(ref.dropFirst(6).dropLast(4)) + ".png"
        return URL(string: "https://cdn.sanity.io/images/5e2ms6sb/production/" + file)
    }

}

struct JARVISMobileProjectsView: View {
    struct Article: Decodable, Identifiable {
        let title: String
        let slug: String
        var id: String { slug }
    }
    struct Reply: Decodable { let result: [Article] }

    @ObservedObject var nearby: JARVISMobileNearbyCalendar
    @State private var articles: [Article]?
    @State private var checkedAt: Date?
    @State private var publicError: String?
    @State private var loading = false
    @State private var showingPairing = false
    @State private var showingArticles = false
    @State private var selectedReview: JARVISReviewArticle?
    @State private var confirmingPublication = false

    private var pendingReviews: [JARVISReviewArticle] {
        guard let articles, publicError == nil else { return [] }
        return (nearby.projectSnapshot?.reviews ?? [])
            .filter { review in !articles.contains { $0.slug == review.slug } }
            .sorted { ($0.topicNumber ?? Int.max, $0.slug) < ($1.topicNumber ?? Int.max, $1.slug) }
    }

    private func isFirstReview(_ review: JARVISReviewArticle) -> Bool {
        review.topicNumber != nil && pendingReviews.first?.id == review.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("DECHIVE Knowledge").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(JARVISPalette.gold)
                }
                .disabled(loading)
                .accessibilityLabel("프로젝트 새로고침")
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("실제 공개 발행").font(.subheadline).foregroundStyle(JARVISPalette.muted)
                Text(articles.map { "\($0.count)편" } ?? "—")
                    .font(.system(size: 36, weight: .semibold, design: .monospaced))
                    .foregroundStyle(JARVISPalette.gold)
                if let checkedAt {
                    Text("공개 CMS 확인 · " + checkedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(JARVISPalette.muted)
                }
                if loading { ProgressView().tint(JARVISPalette.gold) }
                if let publicError { Text(publicError).font(.caption).foregroundStyle(.orange) }
                if let articles {
                    DisclosureGroup("공개 글 목록", isExpanded: $showingArticles) {
                        ForEach(articles) { article in
                            Text(article.title).font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5)
                        }
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 15))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Mac 작업 현황").font(.headline)
                    Spacer()
                    Button { showingPairing = true } label: {
                        Image(systemName: "link").foregroundStyle(JARVISPalette.gold)
                    }
                    .accessibilityLabel("Mac 보안 연결")
                }
                Text(nearby.connectionSummary).font(.caption).foregroundStyle(JARVISPalette.gold)
                Text(nearby.projectStatus)
                    .font(.caption).foregroundStyle(JARVISPalette.muted)
                if let snapshot = nearby.projectSnapshot {
                    Text("기록 확인 " + (ISO8601DateFormatter().date(from: snapshot.checkedAt)
                        .map { $0.formatted(date: .abbreviated, time: .standard) } ?? snapshot.checkedAt))
                        .font(.caption).foregroundStyle(JARVISPalette.muted)
                    if let planned = snapshot.planned { Text("전체 집필 계획  \(planned)개 주제") }
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        Text("일일 집필 현황").font(.headline)
                        Text(snapshot.day + " · 한국 시간").font(.caption)
                            .foregroundStyle(JARVISPalette.muted)
                        HStack {
                            Text(snapshot.repairStarts == nil ? "기존 실행 (복구 포함)" : "신규 집필 시작")
                            Spacer()
                            Text("\(snapshot.starts) / \(snapshot.limit)회")
                                .font(.system(.title3, design: .monospaced).weight(.semibold))
                                .foregroundStyle(JARVISPalette.gold)
                        }
                        if let done = snapshot.dailyStagedCount {
                            HStack {
                                Text("오늘 검토 등록")
                                Spacer()
                                Text("\(done) / \(snapshot.limit)편").foregroundStyle(JARVISPalette.gold)
                            }
                        }
                        if let repairs = snapshot.repairStarts, let repairLimit = snapshot.repairLimit {
                            HStack {
                                Text("복구 작업")
                                Spacer()
                                Text("\(repairs) / \(repairLimit)회")
                            }
                        }
                        Text(snapshot.starts == 0
                             ? "해당 날짜 신규 집필 시작 기록 없음"
                             : "실행 횟수 · 검토 등록 및 공개 발행과 별개")
                            .font(.caption).foregroundStyle(JARVISPalette.muted)
                        if let reason = snapshot.nightReason { Text("야간 작업 종료: " + reason) }
                        if let staged = snapshot.nightStaged, !staged.isEmpty {
                            Text("검토 등록 기록: " + staged)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        Text("최근 작업 기록").font(.headline)
                        Text("이전 작업도 포함 · 다음 집필 예정 주제가 아님")
                            .font(.caption).foregroundStyle(JARVISPalette.muted)
                        if let title = snapshot.latestTitle {
                            Text(title).font(.subheadline.weight(.semibold))
                            let matchingReviews = (snapshot.reviews ?? []).filter { $0.title == title }
                            if let articles, matchingReviews.count == 1,
                               articles.contains(where: { $0.slug == matchingReviews[0].slug }) {
                                Text("공개 CMS 발행 확인").foregroundStyle(JARVISPalette.gold)
                            } else if snapshot.reviewRecorded == true {
                                Text("검토 등록 기록 있음 · 공개 발행과 별개")
                                    .foregroundStyle(JARVISPalette.gold)
                            } else if let state = snapshot.latestState {
                                Text(["running":"집필 중 기록", "artifactsReady":"산출물 생성 완료 기록", "failed":"실패 기록", "incomplete":"미완료 기록", "cancelled":"중단 기록"][state] ?? "상태 확인 필요")
                            }
                        } else {
                            Text("최근 작업 기록 없음").font(.caption)
                                .foregroundStyle(JARVISPalette.muted)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("다음 집필 주제").font(.headline)
                        Text("자동화가 실제 CMS를 대조해 선정합니다. 확정된 주제는 아직 별도로 제공되지 않습니다.")
                            .font(.caption).foregroundStyle(JARVISPalette.muted)
                    }
                } else {
                    Text("집필·검토 기록은 기존 12자리 보안 연결 후 확인할 수 있어요.")
                        .font(.subheadline).foregroundStyle(JARVISPalette.muted)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 15))
            if let message = nearby.publishStatus {
                Text(message).font(.subheadline).foregroundStyle(JARVISPalette.gold)
            }
            if nearby.publishing { ProgressView("발행 처리 중").tint(JARVISPalette.gold) }
            if articles != nil, publicError == nil, nearby.projectSnapshot?.reviews != nil {
                let pending = pendingReviews
                if !pending.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("발행 대기 · \(pending.count)편").font(.headline)
                        Text("목차 순서대로 발행합니다. 뒤 원고는 먼저 읽을 수 있지만 발행은 앞 원고 완료 후 가능합니다.")
                            .font(.caption).foregroundStyle(JARVISPalette.muted)
                        ForEach(Array(pending.enumerated()), id: \.element.id) { index, review in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("발행 대기 순서 \(index + 1) / \(pending.count)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(JARVISPalette.gold)
                                Text(review.numberedTitle).font(.subheadline)
                                Text(isFirstReview(review) ? "다음 발행 대상" : "앞 원고 발행 대기")
                                    .font(.caption).foregroundStyle(JARVISPalette.muted)
                                Button(isFirstReview(review) ? "원고 확인 및 발행" : "원고 미리보기") { selectedReview = review }
                                    .buttonStyle(.borderedProminent)
                                    .tint(JARVISPalette.gold)
                                    .foregroundStyle(JARVISPalette.black)
                                    .disabled((!nearby.connected && !nearby.remoteProjectVerified) || nearby.publishing)
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 15))
                }
            }
            Text("잠금화면 발행 알림 · APNs 연결 전")
                .font(.caption).foregroundStyle(JARVISPalette.muted)
        }
        .sheet(isPresented: $showingPairing) { JARVISCalendarPairingView(nearby: nearby) }
        .sheet(item: $selectedReview) { review in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(review.numberedTitle).font(.title2.bold())
                        if let index = pendingReviews.firstIndex(where: { $0.id == review.id }) {
                            Text("발행 대기 순서 \(index + 1) / \(pendingReviews.count)")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(JARVISPalette.gold)
                        }
                        if !isFirstReview(review) {
                            Text("앞선 목차 원고의 발행을 먼저 완료하세요.")
                                .font(.caption).foregroundStyle(JARVISPalette.muted)
                        }
                        ForEach(["cover.png","body-01.png"], id: \.self) { name in
                            if let url = review.imageURL(name) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image { image.resizable().scaledToFit() }
                                    else if phase.error != nil { Text("이미지 조회 실패: " + name) }
                                    else { ProgressView() }
                                }
                            }
                        }
                        Text(review.article).font(.body).textSelection(.enabled)
                    }.padding()
                }
                .navigationTitle("발행 검토")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    Button("내용 확인 완료 · 발행") {
                        confirmingPublication = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(JARVISPalette.gold)
                    .foregroundStyle(JARVISPalette.black)
                    .disabled(!nearby.canPublish || !isFirstReview(review))
                    .confirmationDialog("실제 사이트에 공개하시겠습니까?", isPresented: $confirmingPublication, titleVisibility: .visible) {
                        Button("공개 발행 승인") {
                            guard isFirstReview(review) else { return }
                            nearby.publish(review)
                            selectedReview = nil
                        }
                        Button("취소", role: .cancel) {}
                    } message: {
                        Text(review.numberedTitle + "\n목차 순서와 검토한 원고 버전을 다시 확인한 후 공개합니다.")
                    }
                    .padding()
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { selectedReview = nil }
                }}
            }
        }
        .onChange(of: nearby.publishRevision) { _, _ in Task { await refresh() } }
        .task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        nearby.refreshProjects()
        guard !loading else { return }
        loading = true
        defer { loading = false }
        var url = URLComponents(string: "https://5e2ms6sb.api.sanity.io/v2026-09-16/data/query/production")!
        url.queryItems = [
            URLQueryItem(name: "query", value: #"*[_type=="knowledge" && status=="published" && humanVerified==true && defined(slug.current)]{title,"slug":slug.current}"#),
            URLQueryItem(name: "perspective", value: "published")
        ]
        do {
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let result = try JSONDecoder().decode(Reply.self, from: data).result
            guard Set(result.map(\.slug)).count == result.count else { throw CocoaError(.fileReadCorruptFile) }
            articles = result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            checkedAt = Date()
            publicError = nil
        } catch {
            if !Task.isCancelled { publicError = articles == nil ? "공개 현황 조회 실패" : "갱신 실패 · 마지막 확인값 표시" }
        }
    }
}
