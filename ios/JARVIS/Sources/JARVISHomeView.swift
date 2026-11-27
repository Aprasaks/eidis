import SwiftUI

/// First native iPhone companion to the current macOS JARVIS.
/// The primary Mac golden core video is real; Mac remote control is not yet paired.
struct JARVISHomeView: View {
    /// 아래 탭 막대에 있는 화면. 나머지는 상단 뒤로가기 버튼을 보여준다.
    static let tabPages: Set<JARVISMobilePage> = [.alarm, .calendar, .core, .approval, .memory]
    /// 하단 탭 순서: 알람 · 일정 · 코어(가운데, 앱을 켜면 항상 여기) · 승인 · 기억
    static let tabOrder: [JARVISMobilePage] = [.alarm, .calendar, .core, .approval, .memory]
    /// 코어 탭의 프로젝트 사이트 (맥 대시보드 사이트 카드와 같은 목록)
    static let sites: [(title: String, domain: String, url: String, symbol: String)] = [
        ("DECHIVE.DEV", "dechive.dev", "https://dechive.dev", "book.closed"),
        ("DECHIVE.APP", "dechive.app", "https://dechive.app", "square.stack.3d.up"),
        ("GUNSAN.COM", "군산.com", "https://xn--6e0b287a.com", "map"),
        ("GUNSAN TABLE TENNIS", "gunsan-table-tennis-association.vercel.app", "https://gunsan-table-tennis-association.vercel.app", "figure.table.tennis")
    ]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var voice = JARVISVoice()
    @AppStorage(JARVISWakeConfirmation.timestampKey) private var lastWakeConfirmedAt = 0.0
    @StateObject private var alarms = JARVISAlarmStore()
    @StateObject private var calendar: JARVISCalendarStore
    @StateObject private var nearby: JARVISMobileNearbyCalendar

    init() {
        let calendar = JARVISCalendarStore(notifications: .current())
        _calendar = StateObject(wrappedValue: calendar)
        _nearby = StateObject(wrappedValue: JARVISMobileNearbyCalendar(calendar: calendar))
    }
    @State private var selectedPage: JARVISMobilePage = JARVISMobilePage.initialPageForVerification
    @State private var prompt = ""
    @State private var messages: [JARVISChatLine] = JARVISChatLine.load()
    @State private var showingPairing = false
    /// 마지막 입력이 마이크였을 때만 답을 소리 내어 읽는다.
    @State private var speakReplies = false
    @State private var proposedEvent: JARVISCalendarDraft?
    @State private var showingCalendarManualEntry = false
    @State private var showingAlarmManualEntry = false
    @FocusState private var inputFocused: Bool

    private var active: Bool {
        scenePhase == .active && !reduceMotion
    }

    var body: some View {
        ZStack {
            JARVISPalette.black.ignoresSafeArea()

            RadialGradient(
                colors: [JARVISPalette.gold.opacity(0.085), .clear],
                center: UnitPoint(x: 0.5, y: 0.43),
                startRadius: 26,
                endRadius: 360
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)
                    .padding(.horizontal, 23)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if selectedPage == .core {
                            greeting
                            sitesSection
                                .padding(.top, 22)
                            chatSection
                                .padding(.top, 22)
                        } else if selectedPage == .memory {
                            JARVISMemoryTabView(calendar: calendar, nearby: nearby)
                        } else if selectedPage == .alarm {
                            JARVISAlarmView(store: alarms)
                        } else if selectedPage == .dashboard {
                            JARVISMobileDashboardView(calendar: calendar, nearby: nearby) { destination in
                                selectedPage = destination
                            }
                        } else {
                            // 아래 탭에 없는 화면(SNS·프로젝트·뉴스 등)은 상단 "‹ 코어" 버튼과
                            // 왼쪽 가장자리 밀기로 코어 탭으로 돌아간다.
                            if !Self.tabPages.contains(selectedPage) {
                                Button { selectedPage = .core } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                                        Text("코어").font(.system(size: 15))
                                    }
                                    .foregroundStyle(JARVISPalette.gold)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("코어로 돌아가기")
                            }
                            JARVISMobileDataPageView(page: selectedPage, calendar: calendar, nearby: nearby)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .id(selectedPage)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    // 왼쪽 가장자리(32pt 이내)에서 오른쪽으로 밀면 뒤로가기 (iOS 기본 동작과 같은 방향).
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard !Self.tabPages.contains(selectedPage), value.startLocation.x < 32,
                                  value.translation.width > 80, abs(value.translation.height) < 70 else { return }
                            selectedPage = .core
                        }
                )

                // 입력창은 코어 탭에서만, 탭바 바로 위에. 키보드가 올라오면 탭바는 숨긴다.
                if selectedPage == .core { composer }
                if !inputFocused { navigationBar }
            }
        }
        .foregroundStyle(JARVISPalette.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingPairing) {
            JARVISCalendarPairingView(nearby: nearby)
        }
        .sheet(item: $proposedEvent) { proposal in
            JARVISCalendarEditor(store: calendar, proposal: proposal, selectedDate: proposal.startAt)
        }
        .sheet(isPresented: $showingCalendarManualEntry) {
            JARVISCalendarEditor(store: calendar)
        }
        .sheet(isPresented: $showingAlarmManualEntry) {
            JARVISAlarmEditor(store: alarms)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                voice.cancel()
                voice.stopSpeaking()
            }
        }
        .onDisappear {
            voice.cancel()
            voice.stopSpeaking()
        }
        .task {
            nearby.setForeground(scenePhase == .active)
            await calendar.rescheduleUpcomingReminders()
            alarms.refresh()
        }
        .onChange(of: messages.count) { _, _ in JARVISChatLine.save(messages) }
        .onChange(of: calendar.localRevision) { _, _ in
            nearby.sync()
        }
        .onOpenURL { url in
            // 위젯을 누르면 SNS 화면으로 (jarvis://social)
            if url.scheme == "jarvis", let host = url.host, let page = JARVISMobilePage(rawValue: host) { selectedPage = page }
        }
        .onChange(of: scenePhase) { _, phase in
            nearby.setForeground(phase == .active)
            // 앱을 열 때마다 SNS 요약을 받아 위젯도 최신으로 맞춘다 (연결된 Mac이 있을 때만).
            if phase == .active { Task { try? await Task.sleep(for: .seconds(2)); nearby.refreshSocial() } }
            if phase == .active {
                nearby.sync()
                alarms.refresh()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("EIDIS")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .tracking(4)
            Spacer()
            // 돌아가는 금빛 코어는 코어 탭에서만, 오른쪽 위에 작게.
            if selectedPage == .core { coreArea }
        }
        .frame(height: 58)
    }

    private var coreArea: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [JARVISPalette.gold.opacity(voice.isListening ? 0.30 : 0.16), .clear],
                    center: .center, startRadius: 4, endRadius: 40))
                .frame(width: 78, height: 78)
                .blur(radius: 8)
            // 맥 이디스 원본 금빛 코어 영상 (작게)
            if let videoURL = Bundle.main.url(forResource: "DECHIVE_Core_Mobile", withExtension: "mp4") {
                JarvisLoopingCoreMobile(videoURL: videoURL, active: active)
                    .frame(width: 58, height: 58)
                    .mask {
                        RadialGradient(stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.78),
                            .init(color: .clear, location: 1)
                        ], center: .center, startRadius: 0, endRadius: 32)
                    }
                    .accessibilityLabel(voice.isListening ? "이디스 코어 · 듣는 중" : "이디스 코어")
                    .accessibilityAddTraits(.isImage)
            } else {
                Image(systemName: "circle.hexagongrid").foregroundStyle(JARVISPalette.gold)
            }
        }
        .frame(width: 58, height: 58)
    }

    private var greeting: some View {
        VStack(spacing: 10) {
            Text("안녕하세요 DECHIVE!")
                .font(.system(size: 23, weight: .medium))
                .tracking(-0.7)
                .multilineTextAlignment(.center)
            macLinkLine
            if lastWakeConfirmedAt > 0,
               Calendar.current.isDateInToday(Date(timeIntervalSince1970: lastWakeConfirmedAt)) {
                Label("기상 확인 완료", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(JARVISPalette.gold)
            }
            if voice.isListening {
                Text("듣고 있어요")
                    .font(.system(size: 12))
                    .foregroundStyle(JARVISPalette.gold)
            }
        }
        .padding(.top, 2)
    }

    /// 맥북과는 한 번만 등록한다. 등록 뒤에는 "동기화 완료"를 두고 지금 연결 방법만 바꿔 보여준다.
    @ViewBuilder private var macLinkLine: some View {
        let link = nearby.macLink
        let color: Color = switch link {
        case .nearby, .remote: Color(red: 0.42, green: 0.86, blue: 0.55)
        case .offline: JARVISPalette.muted
        case .checking, .unpaired: JARVISPalette.goldDim
        }
        Button {
            if link == .unpaired { showingPairing = true }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: link == .offline ? "moon.fill" : link == .unpaired ? "link" : "circle.fill")
                        .font(.system(size: link == .offline || link == .unpaired ? 10 : 7))
                        .foregroundStyle(color)
                    Text(link.routeLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(link == .unpaired ? JARVISPalette.gold : JARVISPalette.white.opacity(0.82))
                }
                if let detail = link.detail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(JARVISPalette.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(link != .unpaired)
        .accessibilityLabel(link.routeLabel)
    }

    private var sitesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("내 프로젝트")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(JARVISPalette.muted)
            ForEach(Self.sites, id: \.url) { site in
                if let url = URL(string: site.url) {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            Image(systemName: site.symbol)
                                .font(.system(size: 16, weight: .light))
                                .foregroundStyle(JARVISPalette.gold)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.title)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(JARVISPalette.white)
                                Text(site.domain)
                                    .font(.system(size: 10))
                                    .foregroundStyle(JARVISPalette.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                                .foregroundStyle(JARVISPalette.muted)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(JARVISPalette.panelEdge, lineWidth: 0.75))
                    }
                    .accessibilityHint("Safari에서 사이트를 엽니다")
                }
            }
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("대화")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(JARVISPalette.muted)
            if messages.isEmpty {
                Text("이디스에게 말을 걸어 보세요. 알람·일정을 말로 잡거나 화면을 열 수 있어요.")
                    .font(.system(size: 13))
                    .foregroundStyle(JARVISPalette.muted)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JARVISPalette.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 13))
            }
            ForEach(messages) { line in
                HStack {
                    if line.fromOwner { Spacer(minLength: 40) }
                    VStack(alignment: line.fromOwner ? .trailing : .leading, spacing: 3) {
                        Text(line.fromOwner ? "DECHIVE" : "EIDIS")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(line.fromOwner ? JARVISPalette.muted : JARVISPalette.gold)
                        Text(line.text)
                            .font(.system(size: 14))
                            .foregroundStyle(line.pending ? JARVISPalette.muted : JARVISPalette.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(line.fromOwner ? JARVISPalette.gold.opacity(0.16) : JARVISPalette.panel,
                                        in: RoundedRectangle(cornerRadius: 14))
                    }
                    if !line.fromOwner { Spacer(minLength: 40) }
                }
            }
            if voice.isListening {
                Text("듣고 있어요…")
                    .font(.system(size: 12))
                    .foregroundStyle(JARVISPalette.gold)
            }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            ForEach(Self.tabOrder) { page in
                Button {
                    selectedPage = page
                    inputFocused = false
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: page.icon)
                            .font(.system(size: 17, weight: .medium))
                        Text(page.title)
                            .font(.system(size: 10, weight: selectedPage == page ? .semibold : .regular))
                    }
                    .foregroundStyle(selectedPage == page ? JARVISPalette.gold : JARVISPalette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 51)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
        .background(JARVISPalette.black)
        .overlay(alignment: .top) {
            JARVISPalette.panelEdge.frame(height: 0.5)
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("이디스에게 말하기…", text: $prompt)
                .font(.system(size: 14))
                .submitLabel(.send)
                .focused($inputFocused)
                .onSubmit(submitPrompt)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(JARVISPalette.panel, in: Capsule())
                .overlay(Capsule().stroke(JARVISPalette.panelEdge))
                .accessibilityLabel("이디스 텍스트 명령")

            if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: submitPrompt) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 39))
                        .foregroundStyle(JARVISPalette.gold)
                }
                .accessibilityLabel("메시지 전송")
            } else {
                Button {
                    toggleMicrophone()
                } label: {
                    Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(JARVISPalette.black)
                        .frame(width: 48, height: 48)
                        .background(JARVISPalette.gold, in: Circle())
                }
                .disabled(voice.busy)
                .accessibilityLabel(voice.isListening ? "음성 인식 완료" : "음성 인식 시작")
            }
        }
        .padding(.horizontal, 19)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(JARVISPalette.black.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(JARVISPalette.gold.opacity(0.13))
                .frame(height: 0.5)
        }
    }

    private func toggleMicrophone() {
        inputFocused = false
        if voice.isListening {
            Task {
                if let text = await voice.finish() {
                    dispatch(text, spoken: true)
                }
            }
        } else {
            Task { await voice.start() }
        }
    }

    private func submitPrompt() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt = ""
        inputFocused = false
        dispatch(text, spoken: false)
    }

    /// 대화 기록에 남기고 말한다 (코어 탭 대화창).
    /// 글자로 친 대화는 조용히, 마이크로 말한 대화만 소리 내어 답한다 (맥과 같은 규칙).
    private func reply(_ answer: String, for input: String) {
        messages.append(JARVISChatLine(fromOwner: false, text: answer))
        if messages.count > 40 { messages.removeFirst(messages.count - 40) }
        if speakReplies { voice.speak(answer, for: input) }
    }

    private func dispatch(_ input: String, spoken: Bool) {
        speakReplies = spoken
        messages.append(JARVISChatLine(fromOwner: true, text: input))
        let compact = input.lowercased().replacingOccurrences(of: " ", with: "")
        if (["알람", "모닝콜", "깨워"].contains { compact.contains($0) }) &&
           (["맞춰", "설정", "추가", "등록", "깨워"].contains { compact.contains($0) }) {
            selectedPage = .alarm
            showingAlarmManualEntry = true
            reply("DECHIVE, 이디스 알람 작성 화면을 열었어요. 시간을 확인하고 저장을 눌러 주세요.", for: input)
            return
        }
        if let proposal = JARVISCalendarSpeechParser.parse(input) {
            selectedPage = .calendar
            proposedEvent = proposal
            reply("DECHIVE, \(proposal.evidence)으로 이해했어요. 내용을 확인하고 저장을 눌러 주세요.", for: input)
            return
        }
        if JARVISCalendarSpeechParser.requestsCreation(input) {
            selectedPage = .calendar
            showingCalendarManualEntry = true
            reply("DECHIVE, 날짜나 오전·오후가 불분명해요. 일정 확인 화면에서 정확한 시간을 지정해 주세요.", for: input)
            return
        }
        if let page = JARVISMobilePage.requestedPage(for: input) {
            selectedPage = page
            reply(page.spokenStatus, for: input)
            return
        }
        askQwen(input)
    }

    /// 화면 이동·알람·일정이 아닌 말은 맥에 상주 중인 Qwen에게 보낸다 (기획서 P7 M1).
    /// 맥이 연결되지 않았으면 폰 안의 간단한 응답으로 대신한다.
    private func askQwen(_ input: String) {
        guard nearby.macLink != .unpaired else {
            reply(JARVISCommand.response(to: input), for: input)
            return
        }
        // 이번 질문 앞까지의 대화만 맥에 함께 보낸다 (최근 8개).
        let history: [[String: String]] = messages.dropLast().filter { !$0.pending }.suffix(8).map {
            ["role": $0.fromOwner ? "user" : "assistant", "content": $0.text]
        }
        let pendingID = UUID()
        messages.append(JARVISChatLine(id: pendingID, fromOwner: false, text: "생각 중…", pending: true))
        nearby.sendChat(input, history: history) { answer, _ in
            messages.removeAll { $0.id == pendingID }
            if let answer {
                reply(answer, for: input)
            } else {
                reply("맥북이 지금 답하지 않아요. 맥이 자고 있거나 꺼져 있을 수 있어요. " +
                      JARVISCommand.response(to: input), for: input)
            }
        }
    }
}

/// 코어 탭 한 줄 연결 표시
enum JARVISMacLink {
    case unpaired, nearby, remote, offline, checking

    var routeLabel: String {
        switch self {
        case .unpaired: "맥북 등록하기"
        case .nearby: "맥북 동기화 완료 · 같은 Wi-Fi"
        case .remote: "맥북 동기화 완료 · Tailscale 원격"
        case .offline: "맥북 동기화 완료 · 지금은 연결 안 됨"
        case .checking: "맥북 동기화 완료 · 연결 확인 중"
        }
    }
    var detail: String? {
        self == .offline ? "맥북이 자고 있거나 꺼져 있어요" : nil
    }
}

struct JARVISChatLine: Identifiable, Codable {
    var id = UUID()
    let fromOwner: Bool
    let text: String
    /// 맥 Qwen의 답을 기다리는 동안 보여주는 임시 말풍선
    var pending = false

    /// 앱을 껐다 켜도 최근 대화 40개는 이 아이폰 안에 남긴다 (어디로도 보내지 않음).
    private static let storeKey = "eidis.chat.history.v1"
    static func load() -> [JARVISChatLine] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let lines = try? JSONDecoder().decode([JARVISChatLine].self, from: data) else { return [] }
        return lines.filter { !$0.pending }
    }
    static func save(_ lines: [JARVISChatLine]) {
        let kept = Array(lines.filter { !$0.pending }.suffix(40))
        if let data = try? JSONEncoder().encode(kept) { UserDefaults.standard.set(data, forKey: storeKey) }
    }
}

#Preview {
    JARVISHomeView()
}
