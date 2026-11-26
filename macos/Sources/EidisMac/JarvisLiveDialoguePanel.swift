import AppKit
import SwiftUI

/// A session-only live transcript. Never archives microphone audio or partial
/// transcriptions. The amber draft is only actual SFSpeechRecognizer output,
/// not an AI guess of what the person will say next.
struct JarvisLiveDialoguePanel: View {
    @ObservedObject var dialogue: JarvisOverlayConversation
    var quiet: Bool = false
    @State private var draftText = ""
    @State private var blinkingCaret = false
    @FocusState private var draftFocused: Bool

    private let amber = Color(red: 0.94, green: 0.67, blue: 0.30)
    private let muted = Color(red: 0.65, green: 0.69, blue: 0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                Text("DECHIVE / LIVE DIALOGUE")
                    .tracking(0.9)
                Spacer(minLength: 0)
                if !quiet {
                    Circle()
                        .fill(dialogue.isListening ? .green : dialogue.isSpeaking ? amber : muted)
                        .frame(width: 7, height: 7)
                    Text(dialogue.isListening ? "LISTENING" :
                         dialogue.isThinking ? "THINKING" :
                         dialogue.isSpeaking ? "SPEAKING" : "READY")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(muted)
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(amber)

            Rectangle().fill(amber.opacity(0.23)).frame(height: 1)
            if !quiet && !dialogue.continuityNotice.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                    Text(dialogue.continuityNotice)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(amber)
                .accessibilityIdentifier("dechive-continuity-notice")
            }

            if !quiet && !dialogue.learning.notice.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                    Text(dialogue.learning.notice)
                        .lineLimit(2)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(amber)
                .accessibilityIdentifier("jarvis-learning-candidate-notice")
            }

            if !quiet && !dialogue.studyNotice.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(dialogue.studyNotice)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(amber)
                .accessibilityIdentifier("dechive-study-notice")
            }

            if !quiet && !dialogue.actionNotice.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                    Text(dialogue.actionNotice)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(amber)
                .accessibilityIdentifier("dechive-action-notice")
            }

            if !dialogue.researchNotice.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "globe.americas.fill")
                        Text("RESEARCH FIELD / 실제 발견 자료")
                            .fontWeight(.semibold)
                        Spacer(minLength: 0)
                        if !quiet {
                            Text(dialogue.researchNotice)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(amber)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(dialogue.researchSources) { source in
                                HStack(alignment: .top, spacing: 7) {
                                    Circle().fill(source.state == "retrieved" ? Color.green :
                                        source.state == "blocked" || source.state == "unavailable" ? amber : muted)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let url = URL(string: source.url),
                                           url.scheme == "https" {
                                            Link(source.title, destination: url)
                                                .font(.system(size: 10, weight: .medium))
                                                .lineLimit(2)
                                        } else {
                                            Text(source.title).font(.system(size: 10)).lineLimit(2)
                                        }
                                        Text(source.domain + " · " + source.stateLabel)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(muted)
                                        if !source.claimedPublishedAt.isEmpty {
                                            Text("출처 표시 날짜(미검증): " + source.claimedPublishedAt)
                                                .font(.system(size: 8))
                                                .foregroundStyle(muted)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 126)
                    .scrollIndicators(.visible)
                }
                .accessibilityIdentifier("dechive-research-field")
            }

            if !dialogue.verificationNotice.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield")
                        Text("VERIFICATION / 인용 원문 대조")
                            .fontWeight(.semibold)
                        Spacer(minLength: 0)
                        if !quiet {
                            Text(dialogue.verificationNotice)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(amber)
                    if !dialogue.verificationClaims.isEmpty {
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(dialogue.verificationClaims) { claim in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(claim.statement)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.88))
                                            .lineLimit(2)
                                        Text("원문 대조: " +
                                             claim.evidence.map { "#\($0.rank)" }.joined(separator: ", ") +
                                             " · 사실성 미검증")
                                            .font(.system(size: 9))
                                            .foregroundStyle(muted)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 86)
                        .scrollIndicators(.visible)
                    }
                }
                .accessibilityIdentifier("dechive-verification-field")
            }

            if let source = dialogue.sourceURL {
                Link(dialogue.sourceTitle.isEmpty ? (source.host ?? "원문") : dialogue.sourceTitle, destination: source)
                    .font(.system(size: 10))
                    .foregroundStyle(amber)
                    .lineLimit(2)
                    .accessibilityLabel("웹페이지 출처: "+source.absoluteString)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(dialogue.dialogueTurns) { turn in
                            VStack(alignment: .leading, spacing: 4) {
                                Text((turn.role == "YOU" ? "오빠" : "DECHIVE") +
                                     (turn.interrupted ? " / INTERRUPTED" : ""))
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(turn.role == "YOU" ? amber : .green.opacity(0.9))
                                Text(turn.content)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(turn.interrupted ? 0.65 : 0.91))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .id(turn.id)
                        }
                        if dialogue.isThinking && !dialogue.streamingAnswer.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(quiet ? "자비스 · 초안" : "JARVIS / 답변 작성 중 · 최종 답변 아님")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(amber)
                                Text(dialogue.streamingAnswer)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .id("streaming")
                        }
                        // Live recognition appears in the editable composer
                        // below, not duplicated in the scrollback area.
                        if !quiet && dialogue.dialogueTurns.isEmpty && !dialogue.isListening {
                            Text("대화를 시작하면 실제 인식 내용과 응답이 이곳에 표시됩니다.")
                                .font(.system(size: 12))
                                .foregroundStyle(muted)
                        }
                        if quiet && dialogue.status.hasPrefix("로컬 Qwen에 연결할 수 없습니다") {
                            Text("지금은 대답하기 어려워요. 잠시 후 다시 말씀해 주세요.")
                                .font(.system(size: 12))
                                .foregroundStyle(muted)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .onChange(of: dialogue.dialogueTurns.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
                }
                .onChange(of: dialogue.liveTranscript) { _, _ in
                    proxy.scrollTo("end", anchor: .bottom)
                }
                .onChange(of: dialogue.streamingAnswer) { _, _ in
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
            if !quiet {
                voiceComposer
            }
        }
        .onChange(of: dialogue.liveTranscript) { _, transcript in
            // Display Apple's real provisional recognition, not fabricated text.
            if dialogue.isListening || !transcript.isEmpty {
                draftText = transcript
            }
        }
        .onChange(of: dialogue.dialogueTurns.count) { _, _ in
            if dialogue.dialogueTurns.last?.role == "YOU" {
                draftText = ""
            }
        }
        .onAppear {
            if dialogue.isListening { draftText = dialogue.liveTranscript }
            // A real insertion caret appears when the dashboard has keyboard
            // focus. The amber cursor signals voice readiness while another
            // monitor owns the keyboard.
            DispatchQueue.main.async { draftFocused = true }
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.035, green: 0.042, blue: 0.055).opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(amber.opacity(0.24)))
        .accessibilityIdentifier("jarvis-live-dialogue-panel")
    }

    private var voiceComposer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(amber.opacity(0.23)).frame(height: 1)
            HStack(spacing: 7) {
                Circle()
                    .fill(dialogue.isListening ? Color.green :
                          dialogue.dashboardDictationEnabled ? amber : muted)
                    .frame(width: 6, height: 6)
                Text(dialogue.isListening ? "LIVE · 음성 받아쓰기" :
                     dialogue.isSpeaking ? "JARVIS · 답변 중" :
                     dialogue.isThinking ? "JARVIS · 처리 중" :
                     dialogue.dashboardDictationEnabled ? dialogue.status : "마이크 꺼짐 · 직접 입력 가능")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(dialogue.isListening ? .green : muted)
                Spacer(minLength: 0)
                Text("받아쓰기 중 · 멈추면 질문 자동 전송")
                    .font(.system(size: 9))
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            HStack(spacing: 7) {
                Button {
                    dialogue.setDashboardDictation(!dialogue.dashboardDictationEnabled)
                } label: {
                    Image(systemName: dialogue.dashboardDictationEnabled ? "mic.fill" : "mic.slash")
                        .font(.system(size: 14))
                        .frame(width: 23, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(dialogue.dashboardDictationEnabled ? amber : muted)
                .help(dialogue.dashboardDictationEnabled ? "연속 받아쓰기 일시정지" : "연속 받아쓰기 재개")
                .accessibilityIdentifier("jarvis-dashboard-dictation-toggle")

                HStack(spacing: 3) {
                    TextField("말씀하거나 입력해 주세요…", text: $draftText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .focused($draftFocused)
                        .onChange(of: draftFocused) { _, focused in
                            dialogue.textInputFocused = focused
                        }
                        .onSubmit {
                            if dialogue.isListening {
                                dialogue.completeUtterance()
                            } else {
                                sendDraft()
                            }
                        }
                        .accessibilityIdentifier("jarvis-dashboard-live-composer")
                    Rectangle()
                        .fill(amber)
                        .frame(width: 1.5, height: 17)
                        // When another monitor owns keyboard focus, native
                        // TextField does not blink. Show the visual voice caret
                        // without taking keyboard focus away from GPT/Codex.
                        .opacity(draftFocused && NSApp.isActive ? 0 :
                                 (blinkingCaret ? 1 : 0))
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                                blinkingCaret = true
                            }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(amber.opacity(0.3)))

                Button {
                    if dialogue.isListening {
                        dialogue.completeUtterance()
                    } else {
                        sendDraft()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(amber)
                }
                .buttonStyle(.plain)
                .disabled(!dialogue.isListening && draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(dialogue.isListening ? "인식한 질문 확정" : "작성한 질문 전송")
                .accessibilityIdentifier("jarvis-dashboard-composer-send")
            }
        }
        .accessibilityIdentifier("jarvis-dashboard-voice-composer")
    }

    private func sendDraft() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        dialogue.submitTyped(text)
        draftText = ""
    }
}
