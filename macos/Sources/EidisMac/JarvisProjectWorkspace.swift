import AppKit
import SwiftUI

enum JarvisWorkroomProject: String, CaseIterable, Identifiable {
    case dev, app, gunsan, tableTennis
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dev: "DECHIVE.DEV"
        case .app: "DECHIVE.APP"
        case .gunsan: "GUNSAN.COM"
        case .tableTennis: "GUNSAN TABLE TENNIS"
        }
    }
    var domain: String {
        switch self {
        case .dev: "dechive.dev"
        case .app: "dechive.app"
        case .gunsan: "gunsan.com"
        case .tableTennis: "gunsan-table-tennis-association.vercel.app"
        }
    }
    var symbol: String {
        switch self {
        case .dev: "book.closed"
        case .app: "square.stack.3d.up"
        case .gunsan: "map"
        case .tableTennis: "figure.table.tennis"
        }
    }
    var accent: Color {
        switch self {
        case .dev: Color(red: 0.94, green: 0.70, blue: 0.32)
        case .app: Color(red: 0.39, green: 0.80, blue: 0.91)
        case .gunsan: Color(red: 0.47, green: 0.83, blue: 0.63)
        case .tableTennis: Color(red: 0.75, green: 0.62, blue: 0.95)
        }
    }
}

extension JarvisAgentID {
    var workroomAccent: Color {
        switch self {
        case .claude: Color(red: 1, green: 0.58, blue: 0.31)
        case .gemini: Color(red: 0.29, green: 0.81, blue: 0.98)
        case .codex: Color(red: 0.94, green: 0.46, blue: 0.76)
        }
    }
}

/// A full-size project workspace, layered over the overview. Only DECHIVE.DEV
/// has a configured job today. Other projects expose their actual URLs only.
struct JarvisProjectWorkspace: View {
    let project: JarvisWorkroomProject
    @ObservedObject var agentBay: JarvisAgentTerminalBay
    @StateObject private var knowledgeCatalog = JarvisKnowledgeCatalogMonitor()

    let close: () -> Void
    private let muted = Color.white.opacity(0.55)
    private let pink = JarvisAgentID.codex.workroomAccent

    var body: some View {
        GeometryReader { geo in
            let scale = min(1.45, max(0.85, geo.size.width / 1460))
            VStack(alignment: .leading, spacing: 16) {
                header(scale)
                Rectangle().fill(project.accent.opacity(0.45)).frame(height: 1)
                if project == .dev {
                    HStack(alignment: .top, spacing: 18) {
                        knowledgeBrief(scale)
                            .frame(width: max(240, geo.size.width * 0.32))
                            .task {
                                while !Task.isCancelled {
                                    await knowledgeCatalog.refresh()
                                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                                }
                            }
                        execution(scale)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("운영 업무 미등록")
                            .font(.system(size: 22 * scale, weight: .medium))
                            .foregroundStyle(project.accent)
                        Text("이 프로젝트의 상세 작업창은 아직 구성하지 않았습니다.")
                            .foregroundStyle(muted)
                        Button("웹사이트 열기") { openSite() }
                            .buttonStyle(.bordered)
                        Spacer()
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.028, green: 0.034, blue: 0.040).opacity(0.98), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(project.accent.opacity(0.58), lineWidth: 1.2))
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("jarvis-project-detail-" + project.rawValue)
    }

    private func header(_ scale: CGFloat) -> some View {
        HStack(spacing: 14) {
            Image(systemName: project.symbol).font(.system(size: 29 * scale, weight: .light))
                .foregroundStyle(project.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title).font(.system(size: 25 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(project.accent)
                Text(project.domain).font(.system(size: 11 * scale, design: .monospaced)).foregroundStyle(muted)
            }
            Spacer()
            Button { openSite() } label: {
                Label("사이트 열기", systemImage: "arrow.up.right")
                    .font(.system(size: 12 * scale))
            }
            .buttonStyle(.bordered)
            Button(action: close) {
                Label("관제실 복귀", systemImage: "xmark")
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(project.accent)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityIdentifier("jarvis-project-detail-close")
        }
    }

    private var stagedTopicCodes: Set<String> {
        // These receipts prove a previous successful staging/readback, not
        // that the draft is still present. Live published state takes priority.
        let root = JarvisKnowledgeCatalog.root.appendingPathComponent("runs", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
        let topics = knowledgeCatalog.catalog?.topics ?? []
        var result = Set<String>()
        for folder in folders {
            guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let topic = topics.first(where: { folder.lastPathComponent.hasPrefix($0.code + "-") }) else { continue }
            let slug = topic.resolvedSlug
            let run = JarvisKnowledgePilotRun(id: UUID(), directory: folder, startedAt: .distantPast, state: .artifactsReady)
            if run.sanityReceipt()?.slug == slug { result.insert(topic.code) }
        }
        return result
    }

    private var activeKnowledgeTopic: JarvisKnowledgeTopic? {
        guard let run = agentBay.knowledgePilot else { return nil }
        return knowledgeCatalog.catalog?.topics.first {
            run.directory.lastPathComponent.hasPrefix($0.code + "-")
        }
    }

    private func topicDisplayName(_ topic: JarvisKnowledgeTopic) -> String {
        let number = String(format: "%03d", topic.number)
        return "\(number)  \(topic.title) (\(topic.code))"
    }

    private func knowledgeBrief(_ scale: CGFloat) -> some View {
        let topics = knowledgeCatalog.catalog?.topics ?? []
        let staged = stagedTopicCodes
        let active = activeKnowledgeTopic
        let next = knowledgeCatalog.nextCandidate(afterStaged: staged)
        let activeRunning = agentBay.knowledgePilot?.state == .running || agentBay.sanityStageRunning
        let focusCode = activeRunning ? active?.code : (next?.code ?? active?.code)
        let published = knowledgeCatalog.publicArticles?.count
        let used = agentBay.knowledgeDailyStarts
        let pending = topics.filter { staged.contains($0.code) && !knowledgeCatalog.isPublished($0) }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("KNOWLEDGE / PROGRESS")
                    .font(.system(size: 13 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(project.accent)
                Spacer(minLength: 0)
                Button {
                    Task { await knowledgeCatalog.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain).foregroundStyle(project.accent)
                .accessibilityLabel("공개 현황 새로고침")
            }
            HStack(alignment: .firstTextBaseline) {
                Text("현재 공개")
                    .font(.system(size: 12 * scale)).foregroundStyle(muted)
                Text(published.map { String($0) } ?? "—")
                    .font(.system(size: 23 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("/ " + (topics.isEmpty ? "—" : String(topics.count)))
                    .font(.system(size: 14 * scale, design: .monospaced)).foregroundStyle(muted)
                Spacer(minLength: 0)
            }
            if let published, !topics.isEmpty {
                ProgressView(value: Double(min(knowledgeCatalog.mappedCount, topics.count)), total: Double(topics.count))
                    .tint(project.accent)
                if published != knowledgeCatalog.mappedCount {
                    Text("목록 연결 확인 \(knowledgeCatalog.mappedCount)편 / 실제 공개 \(published)편")
                        .font(.system(size: 10 * scale)).foregroundStyle(.orange)
                }
            }
            HStack {
                Text((JarvisKnowledgeDailyBudget.usesSeparateRepairs() ? "신규 집필 " : "기존 실행 ") + "\(used) / \(JarvisKnowledgeDailyBudget.limit)")
                    .foregroundStyle(used >= JarvisKnowledgeDailyBudget.limit ? .orange : project.accent)
                Spacer()
                Text("검토 등록 \(pending)")
                    .foregroundStyle(muted)
            }
            .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
            HStack {
                Text("오늘 검토 등록 \(agentBay.knowledgeDailyStaged) / \(JarvisKnowledgeDailyBudget.limit)편")
                    .foregroundStyle(project.accent)
                Spacer()
                if JarvisKnowledgeDailyBudget.usesSeparateRepairs() {
                    Text("복구 \(agentBay.knowledgeDailyRepairs) / \(JarvisKnowledgeDailyBudget.repairLimit)회")
                        .foregroundStyle(muted)
                } else {
                    Text("기존 기록 · 복구 포함").foregroundStyle(muted)
                }
            }
            .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
            HStack {
                Text("00:00 — 01:00 KST")
                    .font(.system(size: 10 * scale, design: .monospaced)).foregroundStyle(muted)
                Spacer()
                Text(agentBay.nightShiftStatus)
                    .font(.system(size: 9 * scale)).foregroundStyle(.orange)
            }
            sectionRule(project.accent)
            Text(activeRunning ? "현재 작업" : "최근 작업")
                .font(.system(size: 10 * scale, weight: .medium)).foregroundStyle(muted)
            if let active {
                Text(topicDisplayName(active))
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .foregroundStyle(activeRunning ? pink : .white)
                    .lineLimit(2)
                Text(agentBay.sanityStageRunning ? "Sanity 등록 중" : knowledgeCatalog.isPublished(active) ? "공개 발행 확인" : staged.contains(active.code) ? "검토 등록 기록 · 미공개" : agentBay.knowledgePilotLabel)
                    .font(.system(size: 11 * scale)).foregroundStyle(activeRunning ? pink : project.accent)
            } else {
                Text("실행 기록 없음").font(.system(size: 11 * scale)).foregroundStyle(muted)
            }
            if let next {
                Text("다음 집필  " + topicDisplayName(next))
                    .font(.system(size: 11 * scale)).foregroundStyle(project.accent).lineLimit(2)
            }
            if let error = knowledgeCatalog.error {
                Text(error).font(.system(size: 10 * scale)).foregroundStyle(.orange)
            }
            sectionRule(project.accent)
            ScrollViewReader { proxy in
                VStack(spacing: 5) {
                    HStack {
                        Text("TOPICS / \(topics.count)")
                            .foregroundStyle(project.accent)
                        Spacer(minLength: 0)
                        Button("처음") {
                            if let first = topics.first { proxy.scrollTo(first.code, anchor: .top) }
                        }.buttonStyle(.plain).foregroundStyle(muted)
                        Button("현재") {
                            if let focusCode { proxy.scrollTo(focusCode, anchor: .center) }
                        }.buttonStyle(.plain).foregroundStyle(project.accent)
                    }
                    .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(topics) { topic in
                                topicRow(topic, staged: staged, activeCode: activeRunning ? active?.code : nil,
                                         nextCode: next?.code, scale: scale)
                                    .id(topic.code)
                            }
                        }
                    }
                    .defaultScrollAnchor(.top)
                    .onChange(of: focusCode, initial: true) { _, code in
                        if let code { proxy.scrollTo(code, anchor: .center) }
                    }
                }
            }
            if let checkedAt = knowledgeCatalog.checkedAt {
                Text("공개 데이터 확인 " + checkedAt.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 9 * scale, design: .monospaced)).foregroundStyle(muted)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(project.accent.opacity(0.30)))
        .accessibilityIdentifier("jarvis-knowledge-catalog-progress")
    }

    private func topicRow(_ topic: JarvisKnowledgeTopic, staged: Set<String>, activeCode: String?, nextCode: String?, scale: CGFloat) -> some View {
        let isPublic = knowledgeCatalog.isPublished(topic)
        let isActive = activeCode == topic.code
        let isStaged = staged.contains(topic.code)
        let isNext = nextCode == topic.code
        let color: Color = isPublic ? .green : isActive ? pink : (isStaged || isNext) ? project.accent : muted
        let label: String
        let symbol: String
        if isPublic { label = "발행"; symbol = "checkmark.circle.fill" }
        else if isActive { label = "작업 중"; symbol = "hourglass" }
        else if isStaged { label = "검토 등록"; symbol = "doc.badge.clock" }
        else if isNext { label = "다음"; symbol = "arrow.right.circle" }
        else { label = knowledgeCatalog.publicArticles == nil || topic.slug == nil ? "미확인" : "미발행"; symbol = "circle" }
        return HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 10 * scale))
                .frame(width: 14 * scale)
            Text(String(format: "%03d", topic.number))
                .font(.system(size: 10 * scale, design: .monospaced)).foregroundStyle(color)
                .frame(width: 27 * scale, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(topic.title).font(.system(size: 11 * scale, weight: isActive || isNext ? .semibold : .regular))
                    .foregroundStyle(isActive || isNext ? .white : .white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                Text(topic.code + " · " + topic.category)
                    .font(.system(size: 9 * scale)).foregroundStyle(muted)
            }
            Spacer(minLength: 2)
            Text(label).font(.system(size: 9 * scale)).foregroundStyle(color)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(isActive || isNext ? color.opacity(0.07) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private func execution(_ scale: CGFloat) -> some View {
        let lane = agentBay.lane(.codex)
        let running = agentBay.knowledgePilot?.state == .running
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "terminal").foregroundStyle(pink)
                Text("CODEX / KNOWLEDGE EXECUTION")
                    .font(.system(size: 15 * scale, weight: .semibold, design: .monospaced)).foregroundStyle(pink)
                Spacer()
                Text(agentBay.knowledgePilotLabel).font(.system(size: 12 * scale, design: .monospaced))
                    .foregroundStyle(running ? .green : muted)
            }
            sectionRule(pink)
            HStack(spacing: 10) {
                Button {
                    agentBay.runKnowledgePilot()
                } label: {
                    // 동작은 그대로(K03-06 이미지 기준 시범 재실행). 이름만 명확히 한다:
                    // 이전 "K03-06 재시험"은 다음 집필(예: 040) 버튼처럼 보여 헷갈렸다.
                    Label("시범 재시험 · K03-06 이미지", systemImage: "play.fill")
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(pink.opacity(0.85))
                .help("예전 시범 원고 K03-06으로 이미지 제작 기준만 다시 시험합니다. 다음 글 집필은 야간 근무(00~01시)가 자동으로 진행합니다.")
                .disabled(agentBay.isAnyRunning || running || agentBay.nightShiftRunning || agentBay.knowledgeDailyLimitReached)
                .accessibilityIdentifier("jarvis-knowledge-pilot-start")
                Button("중단") { agentBay.cancel(.codex) }
                    .buttonStyle(.bordered)
                    .disabled(!running && !agentBay.sanityStageRunning && !agentBay.nightShiftRunning)
                    .accessibilityIdentifier("jarvis-knowledge-pilot-stop")
                Button("Sanity 검토 등록") { agentBay.stageKnowledgePilot() }
                    .buttonStyle(.bordered)
                    .disabled(!agentBay.canStageKnowledge || agentBay.nightShiftRunning)
                    .accessibilityIdentifier("jarvis-knowledge-sanity-stage")
                Spacer()
                if let run = agentBay.knowledgePilot {
                    Button("산출물 폴더") { NSWorkspace.shared.open(run.directory) }
                        .buttonStyle(.bordered)
                }
            }
            HStack {
                Toggle("제작 완료 후 Sanity 검토 등록", isOn: $agentBay.stageAfterPilot)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11 * scale))
                    .disabled(agentBay.isAnyRunning || running || agentBay.sanityStageRunning || agentBay.nightShiftRunning)
                Spacer()
                Button("Sanity Studio") {
                    if let url = URL(string: "https://dechive.dev/studio") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.plain).foregroundStyle(pink)
            }
            if let message = agentBay.sanityStageMessage {
                Text(message).font(.system(size: 11 * scale))
                    .foregroundStyle(agentBay.sanityStageRunning ? muted : project.accent)
            } else if let receipt = agentBay.knowledgePilot?.sanityReceipt() {
                Text("마지막 등록 기록: Sanity 검토용 초안 · " + receipt.checkedAt)
                    .font(.system(size: 10 * scale, design: .monospaced)).foregroundStyle(muted)
            }
            if let error = agentBay.knowledgePilotError {
                Text(error).font(.system(size: 12 * scale)).foregroundStyle(.orange).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                ForEach(JarvisKnowledgePilotRun.artifactNames, id: \.self) { name in
                    let exists = agentBay.knowledgePilot?.hasArtifact(name) == true
                    HStack(spacing: 4) {
                        Image(systemName: exists ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(exists ? .green : muted)
                        Text(name).font(.system(size: 10 * scale, design: .monospaced)).lineLimit(1)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            if let run = agentBay.knowledgePilot {
                if run.state != .running {
                    Text(run.hasPassingImageReview() ? "이미지 자체 검수 PASS · 직접 확인 대기" : "이미지 자체 검수 미통과 / 미기록")
                        .font(.system(size: 11 * scale, weight: .medium))
                        .foregroundStyle(run.hasPassingImageReview() ? .green : .orange)
                }
                Text("실제 시작: " + run.startedAt.formatted(date: .abbreviated, time: .standard) +
                     "  /  정규 근무 01:00 종료 · 시범 최대 60분")
                    .font(.system(size: 10 * scale, design: .monospaced)).foregroundStyle(muted)
            }
            Text("REAL CLI OUTPUT").font(.system(size: 10 * scale, weight: .medium, design: .monospaced)).foregroundStyle(pink)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        if agentBay.knowledgePilot == nil {
                            Text("› 시범 실행을 누르면 실제 Codex 출력이 표시됩니다.")
                                .foregroundStyle(muted)
                        } else if lane.logs.isEmpty {
                            Text("› 아직 수신한 CLI 출력 없음").foregroundStyle(muted)
                        } else {
                            ForEach(Array(lane.logs.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .foregroundStyle(Color.white.opacity(0.86))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .font(.system(size: 11 * scale, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .onChange(of: lane.updatedAt) { _, _ in
                    if let last = lane.logs.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(pink.opacity(0.22)))
            .frame(maxHeight: .infinity)
            Text("파일 체크는 존재 여부입니다. 생성 완료는 독립 검증 또는 실제 발행 성공을 의미하지 않습니다.")
                .font(.system(size: 11 * scale)).foregroundStyle(muted)
        }
        .padding(19)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [pink.opacity(0.065), .black.opacity(0.52)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(pink.opacity(0.50)))
    }

    private func sectionRule(_ tint: Color) -> some View {
        Rectangle().fill(tint.opacity(0.25)).frame(height: 1)
    }

    private func openSite() {
        if let url = URL(string: "https://" + project.domain) { NSWorkspace.shared.open(url) }
    }
}
