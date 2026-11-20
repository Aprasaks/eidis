import SwiftUI

/// A session-only live transcript. Never archives microphone audio or partial
/// transcriptions. The amber draft is only actual SFSpeechRecognizer output,
/// not an AI guess of what the person will say next.
struct JarvisLiveDialoguePanel: View {
    @ObservedObject var dialogue: JarvisOverlayConversation
    @ObservedObject private var speech = ElevenLabsVoiceService.shared

    private let amber = Color(red: 0.94, green: 0.67, blue: 0.30)
    private let muted = Color(red: 0.65, green: 0.69, blue: 0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                Text("JARVIS / LIVE DIALOGUE")
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

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(dialogue.dialogueTurns) { turn in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(turn.role + (turn.interrupted ? " / INTERRUPTED" : ""))
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
                                Text("YOU / LIVE TRANSCRIPT")
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

            Rectangle().fill(amber.opacity(0.17)).frame(height: 1)
            Toggle(isOn: $dialogue.autoTurnEnabled) {
                Text("말을 멈추면 자동으로 질문 확정")
                    .font(.system(size: 10))
                    .foregroundStyle(muted)
            }
            .toggleStyle(.checkbox)
            if dialogue.autoTurnEnabled {
                HStack {
                    Text("말 끝 대기")
                        .font(.system(size: 10)).foregroundStyle(muted)
                    Slider(value: $dialogue.silenceWaitSeconds, in: 5.0...12.0, step: 0.5)
                        .accessibilityIdentifier("jarvis-live-dialogue-pause-length")
                    Text(String(format: "%.1f초", dialogue.silenceWaitSeconds))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(amber)
                }
            }
            Text("긴 이야기는 자동 확정을 끄고 Space로 끝내세요. 중간에 쉬어도 앞 문장은 유지합니다.")
                .font(.system(size: 9))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("ElevenLabs 말하기 속도")
                    .font(.system(size: 10)).foregroundStyle(muted)
                Slider(value: $speech.responseSpeed, in: 0.8...1.05, step: 0.05)
                    .accessibilityIdentifier("jarvis-live-dialogue-voice-speed")
                Text(String(format: "%.2f", speech.responseSpeed))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(amber)
            }
            Button {
                dialogue.toggleMicrophone()
            } label: {
                Label(dialogue.isListening ? "지금 질문 확정" :
                      dialogue.isSpeaking || dialogue.isThinking ?
                      "응답 중단 · 내가 말하기" : "대화 시작",
                      systemImage: dialogue.isListening ? "checkmark.circle" : "mic")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("jarvis-live-dialogue-interrupt")
            if dialogue.isListening {
                Button("마이크 일시정지") {
                    dialogue.pauseMicrophone()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(muted)
                .accessibilityIdentifier("jarvis-live-dialogue-pause")
            }
            Text("Space로 중단·발화 가능 · 예측 문장은 표시하지 않음")
                .font(.system(size: 9))
                .foregroundStyle(muted)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.035, green: 0.042, blue: 0.055).opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(amber.opacity(0.24)))
        .accessibilityIdentifier("jarvis-live-dialogue-panel")
    }
}
