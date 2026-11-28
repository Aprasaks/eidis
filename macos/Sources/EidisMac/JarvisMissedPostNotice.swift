import AppKit
import Foundation

/// 맥이 잠들어 있거나 이디스가 꺼져 있어서 게시 시간을 놓쳤을 때 폰으로 알려 준다.
///
/// 놓친 글을 아무 시간에나 몰래 올리지 않는다. 해외 독자 기준 시간(인스타 22:00, Threads 09:00 KST)이
/// 중요해서, 승인된 글은 다음 게시 시간에 그대로 올라가고 DECHIVE에게는 놓쳤다는 사실만 알린다.
@MainActor
final class JarvisMissedPostNotice {
    static let shared = JarvisMissedPostNotice()
    private var wakeObserver: NSObjectProtocol?
    private static let seoul = TimeZone(identifier: "Asia/Seoul")!

    struct Window {
        let name: String
        let startMinute: Int
        let endMinute: Int
    }
    static let instagram = Window(name: "인스타", startMinute: 22 * 60, endMinute: 23 * 60 + 30)
    static let threads = Window(name: "Threads", startMinute: 9 * 60, endMinute: 11 * 60)

    /// 다음 게시 시간 안내: "오늘 22:00" / "내일 09:00"
    static func nextLabel(_ window: Window, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let time = String(format: "%02d:%02d", window.startMinute / 60, window.startMinute % 60)
        return (minutes < window.startMinute ? "오늘 " : "내일 ") + time
    }

    func start() {
        check()
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in JarvisMissedPostNotice.shared.check() }
        }
    }

    /// 가장 최근에 끝난 게시 시간대를 돌려준다: (그날 키, 시작 시각).
    static func lastWindow(_ window: Window, now: Date = Date()) -> (day: String, start: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        let today = calendar.startOfDay(for: now)
        let endToday = today.addingTimeInterval(TimeInterval(window.endMinute * 60))
        let day = now >= endToday ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        let f = DateFormatter()
        f.timeZone = seoul
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return (f.string(from: day), day.addingTimeInterval(TimeInterval(window.startMinute * 60)))
    }

    /// 시간대가 지났는데 그날 게시 기록이 없고, 그 전에 승인된 글이 있었으면 "놓침"이다.
    static func missed(_ window: Window, now: Date = Date(),
                       approvedAt: [Date], recordedDays: Set<String>) -> String? {
        let last = lastWindow(window, now: now)
        guard !recordedDays.contains(last.day), approvedAt.contains(where: { $0 < last.start }) else { return nil }
        return last.day
    }

    func check() {
        guard !JarvisSNSPause.paused else { return }   // 긴급 정지 중이면 "놓침"이 아니다
        let runs = JarvisInstagramPublisher.runs()
        func approvedAt(_ dir: URL) -> Date? {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("approval.json")),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let at = json["decidedAt"] as? String else { return nil }
            return ISO8601DateFormatter().date(from: at)
        }
        // 인스타: 아직 게시 안 된 승인 글
        let igApproved = runs.filter { JarvisInstagramPublisher.status(of: $0) == "approved" }.compactMap(approvedAt)
        let igDays = Set(runs.compactMap { JarvisInstagramPublisher.record($0)?["day"] as? String })
        if let day = Self.missed(Self.instagram, approvedAt: igApproved, recordedDays: igDays) {
            notify(Self.instagram, day: day)
        }
        // Threads: 승인됐고 threads.txt가 있는데 아직 안 올라간 글
        let thApproved = runs.filter { dir in
            ["approved", "posted"].contains(JarvisInstagramPublisher.status(of: dir) ?? "")
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent("threads.txt").path)
                && JarvisThreadsPublisher.record(dir) == nil
        }.compactMap(approvedAt)
        let thDays = Set(runs.compactMap { JarvisThreadsPublisher.record($0)?["day"] as? String })
        if let day = Self.missed(Self.threads, approvedAt: thApproved, recordedDays: thDays) {
            notify(Self.threads, day: day)
        }
    }

    private func notify(_ window: Window, day: String) {
        let key = "eidis.missedPost.\(window.name).\(day)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }   // 같은 날은 한 번만
        UserDefaults.standard.set(true, forKey: key)
        let next = Self.nextLabel(window)
        JarvisPushNotifier.shared.send(title: "⏰ \(window.name) 게시를 놓쳤어요",
                                       body: "맥이 잠들어 있었어요. 승인된 글은 \(next)에 올라가요. 지금 올리려면 SNS 방에서 게시를 누르세요.",
                                       page: "approval")
        NSLog("EIDIS missed \(window.name) window \(day)")
    }
}
