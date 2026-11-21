import SwiftUI

/// A session-only live transcript. Never archives microphone audio or partial
/// transcriptions. The amber draft is only actual SFSpeechRecognizer output,
/// not an AI guess of what the person will say next.
struct JarvisLiveDialoguePanel: View {
    @ObservedObject var dialogue: JarvisOverlayConversation
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
                Circle()
                    .fill(dialogue.isListening ? .green : dialogue.isSpeaking ? amber : muted)
                    .frame(width: 7, height: 7)
                Text(dialogue.isListening ? "LISTENING" :
                     dialogue.isThinking ? "THINKING" :
                     dialogue.isSpeaking ? "SPEAKING" : "READY")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(muted)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(amber)

            Rectangle().fill(amber.opacity(0.23)).frame(height: 1)
            if !dialogue.continuityNotice.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                    Text(dialogue.continuityNotice)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(amber)
                .accessibilityIdentifier("dechive-continuity-notice")
            }

            if !dialogue.studyNotice.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(dialogue.studyNotice)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(amber)
                .accessibilityIdentifier("dechive-study-notice")
            }

            if !dialogue.actionNotice.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                    Text(dialogue.actionNotice)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(amber)
                .accessibilityIdentifier("dechive-action-notice")
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(dialogue.dialogueTurns) { turn in
                            VStack(alignment: .leading, spacing: 4) {
                                Text((turn.role == "YOU" ? "주인님" : "DECHIVE") +
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
                        if dialogue.isListening || !dialogue.liveTranscript.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("주인님 / LIVE TRANSCRIPT")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(amber)
                                Text(dialogue.liveTranscript.isEmpty ?
                                     "말씀하시면 여기에 실시간으로 받아적습니다…" : dialogue.liveTranscript)
                                    .font(.system(size: 12))
                                    .foregroundStyle(dialogue.liveTranscript.isEmpty ?
                                                    muted : .white.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                                if !dialogue.liveTranscript.isEmpty {
                                    Text("인식 중 · 아직 확정되지 않은 문장")
                                        .font(.system(size: 9))
                                        .foregroundStyle(muted)
                                }
                            }
                            .id("live")
                        }
                        if dialogue.dialogueTurns.isEmpty && !dialogue.isListening {
                            Text("대화를 시작하면 실제 인식 내용과 응답이 이곳에 표시됩니다.")
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
