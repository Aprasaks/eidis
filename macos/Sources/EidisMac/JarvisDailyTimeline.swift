import SwiftUI

/// 오늘의 자동 작업 시간표 (KST). 모든 상태는 실제 기록에서 읽는다:
/// Knowledge 야간 근무(에이전트 베이), 캐러셀 제작(실행 폴더), 인스타 게시(publish.json),
/// 사이트 점검(JarvisSitePulse). 기록이 없으면 "예정"/"없음"으로만 표시하고 추정하지 않는다.
struct JarvisDailyTimeline {
    enum State { case waiting, running, done, attention, idle }

    struct Item: Identifiable {
        let id: String
        let time: String
        let title: String
        let agent: String
        let state: State
        let detail: String
    }

    let items: [Item]
    let summary: String
    /// 다음 정해진 작업까지 남은 시간 (예: "다음 · Threads 게시 2시간 13분 후")
    var next: String = ""

    @MainActor
    static func build(agentBay: JarvisAgentTerminalBay, carousel: JarvisCarouselRunner,
                      sites: JarvisSitePulse, now: Date = Date()) -> JarvisDailyTimeline {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        var items: [Item] = []

        // 1) 00:00 Knowledge 야간 집필 (Codex)
        let staged = agentBay.knowledgeDailyStaged, starts = agentBay.knowledgeDailyStarts
        let knowledge: (State, String) = agentBay.nightShiftRunning ? (.running, "집필 중 · 실행 \(starts)/3")
            : starts > 0 ? (.done, "검토 등록 \(staged)편 · 실행 \(starts)/3")
            : minutes < 60 ? (.waiting, "00:00~01:00 근무") : (.idle, "오늘 실행 기록 없음")
        items.append(Item(id: "knowledge", time: "00:00", title: "Knowledge 야간 집필", agent: "Codex",
                          state: knowledge.0, detail: knowledge.1))

        // 2) 01:30 인스타 캐러셀 제작 (Claude) → 폰 승인
        let today = carousel.todayScheduled()
        let queue = carousel.approvalQueue()
        let carouselState: (State, String)
        if carousel.isRunning {
            carouselState = (.running, carousel.stage.label + (carousel.meta.map { " · " + $0.title } ?? ""))
        } else if let today {
            switch today.status {
            case "review": carouselState = (.attention, today.title + " · 폰 승인 대기")
            case "approved": carouselState = (.done, today.title + " · 승인됨")
            case "posted": carouselState = (.done, today.title + " · 게시 완료")
            case "rejected": carouselState = (.idle, today.title + " · 반려")
            default: carouselState = (.attention, today.title + " · 제작 실패")
            }
        } else {
            carouselState = minutes < 90 ? (.waiting, "01:30~02:30 자동 제작") : (.idle, carousel.scheduleStatus)
        }
        items.append(Item(id: "carousel", time: "01:30", title: "인스타 캐러셀 제작", agent: "Claude",
                          state: carouselState.0, detail: carouselState.1))

        // 2-1) 09:00 Threads 게시 (자비스 · 승인된 threads.txt만)
        let threadRecord = JarvisInstagramPublisher.runs().lazy
            .compactMap { JarvisThreadsPublisher.record($0) }
            .first { ($0["day"] as? String) == Self.dayKey(now) }
        let threads: (State, String)
        switch threadRecord?["result"] as? String {
        case "posted": threads = (.done, "게시 완료")
        case "publishing": threads = (.running, "게시 중")
        case .some(let result): threads = (.attention, "게시 안 됨 · " + ((threadRecord?["error"] as? String) ?? result))
        case .none:
            if JarvisThreadsPublisher.nextApproved() != nil {
                threads = minutes < 9 * 60 ? (.waiting, "승인된 글 · 09시 게시 예정")
                    : minutes < 11 * 60 ? (.running, "승인된 글 · 게시 대기") : (.waiting, "승인된 글 · 내일 09시 게시")
            } else {
                threads = (.idle, "승인된 Threads 글 없음")
            }
        }
        items.append(Item(id: "threads", time: "09:00", title: "Threads 게시", agent: "자비스",
                          state: threads.0, detail: threads.1))

        // 3) 22:00 인스타 게시 (자비스 · 승인된 것만)
        let record = JarvisInstagramPublisher.runs().lazy
            .compactMap { JarvisInstagramPublisher.record($0) }
            .first { ($0["day"] as? String) == Self.dayKey(now) }
        let publish: (State, String)
        switch record?["result"] as? String {
        case "posted": publish = (.done, "게시 완료")
        case "publishing": publish = (.running, "게시 중")
        case .some(let result): publish = (.attention, "게시 안 됨 · " + ((record?["error"] as? String) ?? result))
        case .none:
            if let title = queue.approvedTitle {
                publish = minutes < 22 * 60 ? (.waiting, title + " · 22시 게시 예정") : (.running, title + " · 게시 대기")
            } else {
                publish = (.idle, "승인된 캐러셀 없음")
            }
        }
        items.append(Item(id: "publish", time: "22:00", title: "인스타 게시", agent: "자비스",
                          state: publish.0, detail: publish.1))

        // 4) 사이트 점검 (15분마다)
        let pulses = Array(sites.pulses.values)
        let ok = pulses.filter { $0.siteOK == true }.count
        let site: (State, String) = pulses.isEmpty ? (.waiting, "확인 중")
            : ok == pulses.count ? (.done, "사이트 \(ok)/\(pulses.count) 정상") : (.attention, "사이트 \(ok)/\(pulses.count) 정상 · 확인 필요")
        items.append(Item(id: "sites", time: "15분", title: "사이트 점검", agent: "자비스",
                          state: site.0, detail: site.1))

        // 한 줄 요약 (코어 아래)
        var parts: [String] = []
        if queue.waiting > 0 { parts.append("폰 승인 대기 \(queue.waiting)") }
        if let title = queue.approvedTitle, record == nil { parts.append("22:00 게시 예정 · " + title) }
        if (record?["result"] as? String) == "posted" { parts.append("오늘 인스타 게시 완료") }
        if staged > 0 { parts.append("Knowledge \(staged)편") }
        if !pulses.isEmpty { parts.append(ok == pulses.count ? "사이트 모두 정상" : "사이트 확인 필요") }
        // 다음 정해진 작업 (KST 고정 시각)
        let fixed: [(Int, String)] = [(0, "Knowledge 야간 집필"), (90, "캐러셀 제작"), (540, "Threads 게시"), (1320, "인스타 게시")]
        let upcoming = fixed.first { $0.0 > minutes } ?? (fixed[0].0 + 1440, fixed[0].1)
        let left = upcoming.0 - minutes
        let nextLabel = "다음 · \(upcoming.1) " + (left >= 60 ? "\(left / 60)시간 \(left % 60)분 후" : "\(left)분 후")
        var timeline = JarvisDailyTimeline(items: items, summary: parts.isEmpty ? "오늘 예정된 작업을 확인하는 중" : parts.joined(separator: "  ·  "))
        timeline.next = nextLabel
        return timeline
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
}

/// 오른쪽 위 "TODAY / 자동 작업 시간표" 패널
struct JarvisDailyTimelinePanel: View {
    let timeline: JarvisDailyTimeline
    let scale: CGFloat
    private let amber = Color(red: 0.94, green: 0.67, blue: 0.30)
    private let muted = Color(red: 0.64, green: 0.66, blue: 0.68)
    private let mint = Color(red: 0.46, green: 0.84, blue: 0.69)

    private func color(_ state: JarvisDailyTimeline.State) -> Color {
        switch state {
        case .running: mint
        case .done: mint.opacity(0.75)
        case .attention: .orange
        case .waiting: amber
        case .idle: muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar.day.timeline.left").foregroundStyle(amber)
                Text("TODAY / 자동 작업 시간표")
                    .font(.system(size: 13 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(amber)
                Spacer()
                Text(timeline.next.isEmpty ? "KST" : timeline.next + " · KST")
                    .font(.system(size: 11 * scale, design: .monospaced)).foregroundStyle(muted)
            }
            Rectangle().fill(amber.opacity(0.25)).frame(height: 1)
            // 행을 세로로 고르게 배치해 패널 아래가 비지 않게 한다.
            ForEach(timeline.items) { item in
                Spacer(minLength: 4)
                HStack(alignment: .top, spacing: 10) {
                    Text(item.time)
                        .font(.system(size: 13 * scale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color(item.state))
                        .frame(width: 46 * scale, alignment: .leading)
                    ZStack {
                        Circle().fill(color(item.state)).frame(width: 8, height: 8)
                        if item.state == .running {
                            Circle().stroke(mint.opacity(0.5), lineWidth: 2).frame(width: 14, height: 14)
                        }
                    }
                    .frame(width: 14, height: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.title).font(.system(size: 14 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                            Text(item.agent).font(.system(size: 10 * scale, design: .monospaced)).foregroundStyle(muted)
                        }
                        Text(item.detail)
                            .font(.system(size: 12 * scale))
                            .foregroundStyle(item.state == .attention ? Color.orange : muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [amber.opacity(0.09), Color.black.opacity(0.62)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(amber.opacity(0.5), lineWidth: 1))
        .accessibilityIdentifier("jarvis-daily-timeline")
    }
}
