import SwiftUI

/// A session-only live transcript. Never archives microphone audio or partial
/// transcriptions. The amber draft is only actual SFSpeechRecognizer output,
/// not an AI guess of what the person will say next.
struct JarvisLiveDialoguePanel: View {
    @ObservedObject var dialogue: JarvisOverlayConversation
    var quiet: Bool = false
    // The presentation-only panel has no settings or action controls.

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
                        if !dialogue.liveTranscript.isEmpty || (!quiet && dialogue.isListening) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(quiet ? "오빠" : "오빠 / LIVE TRANSCRIPT")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(amber)
                                Text(dialogue.liveTranscript.isEmpty ?
                                     "말씀하시면 여기에 실시간으로 받아적습니다…" : dialogue.liveTranscript)
                                    .font(.system(size: 12))
                                    .foregroundStyle(dialogue.liveTranscript.isEmpty ?
                                                    muted : .white.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                                if !quiet && !dialogue.liveTranscript.isEmpty {
                                    Text("인식 중 · 아직 확정되지 않은 문장")
                                        .font(.system(size: 9))
                                        .foregroundStyle(muted)
                                }
                            }
                            .id("live")
                        }
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

        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.035, green: 0.042, blue: 0.055).opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(amber.opacity(0.24)))
        .accessibilityIdentifier("jarvis-live-dialogue-panel")
    }
}
