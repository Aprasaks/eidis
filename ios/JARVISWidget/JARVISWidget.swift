import WidgetKit
import SwiftUI

/// 자비스 위젯: 홈 화면(작게·중간)과 잠금화면(직사각형·한 줄).
/// 앱이 Mac에서 받아 App Group에 저장한 실제 요약만 보여준다. 값이 없으면 "—".
struct JARVISEntry: TimelineEntry {
    let date: Date
    let summary: JARVISWidgetSummary?
}

struct JARVISProvider: TimelineProvider {
    func placeholder(in context: Context) -> JARVISEntry { JARVISEntry(date: Date(), summary: nil) }
    func getSnapshot(in context: Context, completion: @escaping (JARVISEntry) -> Void) {
        completion(JARVISEntry(date: Date(), summary: JARVISWidgetSummary.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<JARVISEntry>) -> Void) {
        // 앱이 새 값을 저장하면 즉시 다시 그린다(reloadAllTimelines). 그 외에는 30분마다 시간 표시만 갱신.
        let entry = JARVISEntry(date: Date(), summary: JARVISWidgetSummary.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

private enum Palette {
    static let gold = Color(red: 1.0, green: 0.66, blue: 0.27)
    static let muted = Color(red: 0.57, green: 0.59, blue: 0.62)
    static let mint = Color(red: 0.46, green: 0.84, blue: 0.69)
    static let black = Color(red: 0.025, green: 0.029, blue: 0.035)
}

private func number(_ value: Int?) -> String { value.map { $0.formatted() } ?? "—" }

private func headline(_ s: JARVISWidgetSummary?) -> String {
    guard let s else { return "이디스를 열어 연결" }
    if s.waitingApprovals > 0 { return "승인 대기 \(s.waitingApprovals)" }
    if s.latestStatus == "posted" { return "오늘 게시 완료" }
    if s.nextPostTitle != nil { return "22시 게시 예정" }
    return "대기 중인 작업 없음"
}

struct JARVISWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JARVISEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("EIDIS · " + headline(entry.summary))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("EIDIS").font(.system(size: 12, weight: .bold, design: .monospaced))
                Text(headline(entry.summary)).font(.system(size: 13, weight: .semibold))
                Text("팔로워 \(number(entry.summary?.globalFollowers)) · YT \(number(entry.summary?.youtubeSubscribers))")
                    .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("EIDIS").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Palette.gold)
                Spacer()
                Circle().fill((entry.summary?.waitingApprovals ?? 0) > 0 ? Palette.gold : Palette.mint).frame(width: 7, height: 7)
            }
            Spacer(minLength: 0)
            Text(headline(entry.summary))
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
            Text("팔로워 \(number(entry.summary?.globalFollowers))").font(.system(size: 12)).foregroundStyle(Palette.muted)
            Text("YouTube \(number(entry.summary?.youtubeSubscribers))").font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EIDIS · SNS").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Palette.gold)
                Text(headline(entry.summary)).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                if let title = entry.summary?.nextPostTitle {
                    Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                if let at = entry.summary?.updatedAt {
                    Text(at, style: .relative).font(.system(size: 10)).foregroundStyle(Palette.muted)
                        + Text(" 전 확인").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                stat("IG", entry.summary?.igFollowers)
                stat("Threads", entry.summary?.threadsFollowers)
                stat("YouTube", entry.summary?.youtubeSubscribers)
            }
        }
    }

    private func stat(_ name: String, _ value: Int?) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(number(value)).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Text(name).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }
}

struct JARVISStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JARVISStatus", provider: JARVISProvider()) { entry in
            JARVISWidgetView(entry: entry)
                .containerBackground(for: .widget) { Palette.black }
                .widgetURL(URL(string: "jarvis://social"))
        }
        .configurationDisplayName("EIDIS")
        .description("승인 대기, 다음 게시, 팔로워와 구독자 수")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct JARVISWidgetBundle: WidgetBundle {
    var body: some Widget { JARVISStatusWidget() }
}
