import SwiftUI

/// dechive.app · 군산.com · 탁구협회 작업실 (이전: "운영 업무 미등록" 한 줄).
/// 모든 값은 공개 사이트·GitHub 공개 API·숫자만 주는 구독 집계에서 실제로 읽는다.
@MainActor
final class JarvisSiteWorkroomModel: ObservableObject {
    struct Row: Identifiable { let id = UUID(); let title: String; let detail: String; var state: Int = 0 }  // state: 0 보통, 1 완료, 2 주의

    @Published var siteLabel = "확인 중…"
    @Published var siteOK: Bool?
    @Published var commits: [Row] = []
    @Published var main: [Row] = []
    @Published var mainTitle = ""
    @Published var stats: [(String, String)] = []
    @Published var checkedAt: Date?
    @Published var loading = false

    func load(_ project: JarvisWorkroomProject) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let (url, repo) = JarvisSitePulse.site(project)
        async let site = JarvisSitePulse.checkSite(url)
        async let commitRows = Self.commits(repo)
        switch project {
        case .app:
            mainTitle = "최근 글 · dechive.app/feed.xml"
            async let posts = Self.feed()
            async let letter = Self.letterStats()
            main = await posts
            stats = await letter
        case .gunsan:
            mainTitle = "리빌드 단계 · REBUILD_STEPS.md"
            main = await Self.rebuildSteps()
            stats = [("상태", "새 작업 대기 중"), ("예정 기능", "지도 · 맛집 · 리뷰 · QR")]
        case .tableTennis:
            mainTitle = "대회 정보 수집 (sync-jbtta-2026) 최근 실행"
            main = await Self.crawlRuns()
            stats = [("상태", "일시 중지 (사용자 요청)"), ("다음", "수집 코드 정확하게 수정 예정")]
        case .dev:
            break
        }
        let (ok, label) = await site
        siteOK = ok
        siteLabel = label
        commits = await commitRows
        checkedAt = Date()
    }

    // MARK: Fetchers (읽기 전용)

    nonisolated private static func json(_ address: String) async -> Any? {
        guard let url = URL(string: address) else { return nil }
        let (status, data, _) = await JarvisSitePulse.get(url, accept: "application/vnd.github+json")
        guard status == 200, let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    nonisolated private static func commits(_ repo: String) async -> [Row] {
        guard let list = await json("https://api.github.com/repos/Aprasaks/\(repo)/commits?per_page=6") as? [[String: Any]] else {
            return [Row(title: "커밋 확인 실패", detail: "GitHub 응답 없음", state: 2)]
        }
        return list.compactMap { item in
            guard let commit = item["commit"] as? [String: Any], let message = commit["message"] as? String,
                  let date = ((commit["committer"] as? [String: Any])?["date"] as? String).flatMap(ISO8601DateFormatter().date(from:))
            else { return nil }
            return Row(title: message.split(separator: "\n").first.map(String.init) ?? message,
                       detail: JarvisSitePulse.relative(date))
        }
    }

    nonisolated private static func feed() async -> [Row] {
        guard let url = URL(string: "https://dechive.app/feed.xml") else { return [] }
        let (status, data, _) = await JarvisSitePulse.get(url)
        guard status == 200, let data else { return [Row(title: "feed.xml 확인 실패", detail: "", state: 2)] }
        let xml = String(decoding: data, as: UTF8.self)
        let tag = xml.contains("<item>") ? "item" : "entry"
        func value(_ name: String, in block: Substring) -> String? {
            guard let open = block.range(of: "<\(name)"), let start = block[open.upperBound...].range(of: ">"),
                  let close = block.range(of: "</\(name)>", range: start.upperBound..<block.endIndex) else { return nil }
            return String(block[start.upperBound..<close.lowerBound])
                .replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return xml.components(separatedBy: "<\(tag)>").dropFirst().prefix(6).map { raw in
            let block = Substring(raw)
            let date = (value("pubDate", in: block) ?? value("published", in: block) ?? value("updated", in: block) ?? "")
            return Row(title: value("title", in: block) ?? "(제목 없음)", detail: String(date.prefix(16)))
        }
    }

    nonisolated private static func letterStats() async -> [(String, String)] {
        guard let secret = JarvisSitePulse.statsSecret(),
              let url = URL(string: "https://letter.dechive.app/api/letter-stats") else { return [("구독자", "집계 연결 필요")] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [("구독자", "확인 실패")] }
        let source = json["bySource"] as? [String: Int] ?? [:]
        return [("구독 중", "\(json["active"] as? Int ?? 0)명"),
                ("메인(dechive.app)", "\(source["dechive.app"] ?? 0)명"),
                ("레터(letter.dechive.app)", "\(source["letter.dechive.app"] ?? 0)명"),
                ("이번 주 신규", "\(json["newThisWeek"] as? Int ?? 0)명"),
                ("해지", "\(json["unsubscribed"] as? Int ?? 0)명")]
    }

    /// "## n단계: 제목 (상태)" 와 "## 다음 단계" 목록을 그대로 읽는다.
    nonisolated private static func rebuildSteps() async -> [Row] {
        guard let url = URL(string: "https://raw.githubusercontent.com/Aprasaks/gunsan-com/main/docs/REBUILD_STEPS.md") else { return [] }
        let (status, data, _) = await JarvisSitePulse.get(url)
        guard status == 200, let data else { return [Row(title: "REBUILD_STEPS.md 확인 실패", detail: "", state: 2)] }
        var rows: [Row] = []      // 단계 (문서 순서)
        var next: [Row] = []      // "다음 단계" 목록은 단계들 뒤에 모아서 보여준다
        var inNext = false
        for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                let heading = String(line.dropFirst(3))
                inNext = heading.contains("다음 단계")
                if !inNext, heading.contains("단계") {
                    let done = heading.contains("반영")
                    let title = heading.components(separatedBy: " (").first ?? heading
                    let note = heading.range(of: "(").map { String(heading[$0.lowerBound...]) } ?? ""
                    rows.append(Row(title: title, detail: note, state: done ? 1 : 0))
                }
            } else if inNext, let match = line.range(of: "^[0-9]+\\. ", options: .regularExpression) {
                next.append(Row(title: String(line[match.upperBound...]), detail: "다음 단계 · 미구현", state: 0))
            }
        }
        rows += next
        return rows.isEmpty ? [Row(title: "단계 정보를 찾지 못함", detail: "", state: 2)] : rows
    }

    nonisolated private static func crawlRuns() async -> [Row] {
        guard let json = await json("https://api.github.com/repos/Aprasaks/gunsan-table-tennis-association/actions/workflows/sync-jbtta-2026.yml/runs?per_page=6") as? [String: Any],
              let runs = json["workflow_runs"] as? [[String: Any]] else {
            return [Row(title: "수집 실행 기록 확인 실패", detail: "", state: 2)]
        }
        return runs.compactMap { run in
            guard let date = (run["created_at"] as? String).flatMap(ISO8601DateFormatter().date(from:)) else { return nil }
            let conclusion = run["conclusion"] as? String ?? "진행 중"
            return Row(title: (conclusion == "success" ? "성공" : conclusion) + " · " + ((run["event"] as? String) == "schedule" ? "자동" : "수동"),
                       detail: JarvisSitePulse.relative(date), state: conclusion == "success" ? 1 : 2)
        }
    }
}

struct JarvisSiteWorkroomBody: View {
    let project: JarvisWorkroomProject
    let scale: CGFloat
    @StateObject private var model = JarvisSiteWorkroomModel()
    private let muted = Color.white.opacity(0.55)
    private let mint = Color(red: 0.46, green: 0.84, blue: 0.69)

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                panel("사이트 상태", icon: "dot.radiowaves.left.and.right") {
                    HStack(spacing: 8) {
                        Circle().fill(model.siteOK == true ? mint : (model.siteOK == false ? Color.orange : muted)).frame(width: 9, height: 9)
                        Text(model.siteLabel).font(.system(size: 18 * scale, weight: .semibold, design: .monospaced))
                    }
                    Text(project.domain)   // 군산.com은 퓨니코드 대신 한글로 표시
                        .font(.system(size: 12 * scale, design: .monospaced)).foregroundStyle(muted)
                    if let at = model.checkedAt {
                        Text(at.formatted(date: .omitted, time: .standard) + " 확인 · 열려 있는 동안 1분마다")
                            .font(.system(size: 11 * scale)).foregroundStyle(muted)
                    }
                }
                panel(project == .app ? "뉴스레터 (letter.dechive.app 통합 명단)" : "현황", icon: "chart.bar") {
                    ForEach(Array(model.stats.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.0).foregroundStyle(muted)
                            Spacer()
                            Text(item.1).font(.system(size: 15 * scale, weight: .semibold)).foregroundStyle(project.accent)
                        }
                        .font(.system(size: 13 * scale))
                    }
                }
            }
            .frame(width: 330 * scale)
            panel(model.mainTitle, icon: "list.bullet.rectangle") { rows(model.main) }
            panel("최근 커밋 · GitHub", icon: "arrow.triangle.branch") { rows(model.commits) }
                .frame(width: 380 * scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            while !Task.isCancelled {
                await model.load(project)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    private func rows(_ items: [JarvisSiteWorkroomModel.Row]) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    Text(model.loading ? "불러오는 중…" : "기록 없음").foregroundStyle(muted)
                }
                ForEach(items) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: row.state == 1 ? "checkmark.circle.fill" : row.state == 2 ? "exclamationmark.triangle" : "circle")
                            .foregroundStyle(row.state == 1 ? mint : row.state == 2 ? Color.orange : muted)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title).font(.system(size: 14 * scale, weight: .medium)).foregroundStyle(.white.opacity(0.92))
                            if !row.detail.isEmpty {
                                Text(row.detail).font(.system(size: 11 * scale)).foregroundStyle(muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func panel<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 13 * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(project.accent)
            Rectangle().fill(project.accent.opacity(0.25)).frame(height: 1)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(project.accent.opacity(0.28)))
    }
}
