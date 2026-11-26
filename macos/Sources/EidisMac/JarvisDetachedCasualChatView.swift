import SwiftUI

/// Native companion window. The gold fullscreen core owns its video player;
/// this view only observes the same local conversation and learning store.
struct JarvisDetachedCasualChatView: View {
    @ObservedObject var dialogue: JarvisOverlayConversation
    @State private var typedText = ""
    @State private var showMemoryReview = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(.orange)
                Text("JARVIS / 일상 채팅")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Button("채팅 닫기") { dialogue.setCasualChatMode(false) }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                    .accessibilityIdentifier("jarvis-casual-chat-close")
            }
            .padding(.horizontal, 17)
            .padding(.top, 13)
            .padding(.bottom, 12)

            Divider().overlay(.orange.opacity(0.45))

            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                Text(dialogue.learning.enabled
                     ? "대화 학습 켜짐 · 승인한 기억만 반영"
                     : "대화 학습 꺼짐 · 채팅은 계속 가능")
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button(dialogue.learning.pendingCount > 0
                       ? "기억 후보 \(dialogue.learning.pendingCount)개"
                       : "기억 설정") {
                    showMemoryReview = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .popover(isPresented: $showMemoryReview, arrowEdge: .bottom) {
                    JarvisLearningReviewView(learning: dialogue.learning)
                        .padding(16)
                        .frame(width: 350)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.70))
            .padding(.horizontal, 17)
            .padding(.vertical, 12)
            .accessibilityIdentifier("jarvis-casual-chat-learning")

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(dialogue.dialogueTurns) { turn in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(turn.role == "YOU" ? "YOU" : "JARVIS")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(turn.role == "YOU" ? .orange : .green)
                                Text(turn.content)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(turn.interrupted ? 0.6 : 0.93))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(turn.id)
                        }
                        if dialogue.isThinking {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("JARVIS / 생각 중")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.orange)
                                Text(dialogue.streamingAnswer.isEmpty
                                     ? "답변을 준비하고 있어요…"
                                     : dialogue.streamingAnswer)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.84))
                                    .textSelection(.enabled)
                            }
                        }
                        if !dialogue.liveTranscript.isEmpty {
                            Text(dialogue.liveTranscript)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        if dialogue.dialogueTurns.isEmpty && !dialogue.isThinking {
                            Text("오늘 있었던 일이나 떠오른 생각을 편하게 이야기해 주세요.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        Color.clear.frame(height: 1).id("chat-end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .scrollIndicators(.visible)
                .onChange(of: dialogue.dialogueTurns.count) { _, _ in
                    proxy.scrollTo("chat-end", anchor: .bottom)
                }
                .onChange(of: dialogue.streamingAnswer) { _, _ in
                    proxy.scrollTo("chat-end", anchor: .bottom)
                }
                .onChange(of: dialogue.liveTranscript) { _, _ in
                    proxy.scrollTo("chat-end", anchor: .bottom)
                }
            }
            .background(Color(red: 0.024, green: 0.028, blue: 0.036))

            if let source = dialogue.sourceURL {
                Link(dialogue.sourceTitle.isEmpty ? (source.host ?? "원문") : dialogue.sourceTitle,
                     destination: source)
                    .font(.system(size: 11))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            Divider().overlay(.white.opacity(0.16))

            HStack(spacing: 9) {
                Button {
                    dialogue.toggleMicrophone()
                } label: {
                    Image(systemName: dialogue.isListening ? "stop.circle.fill" : "mic.fill")
                        .frame(width: 25, height: 27)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.68, green: 0.37, blue: 0.06))
                .accessibilityIdentifier("jarvis-workspace-microphone")

                TextField("편하게 이야기해 주세요…", text: $typedText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .focused($inputFocused)
                    .onChange(of: inputFocused) { _, focused in
                        dialogue.textInputFocused = focused
                    }
                    .onSubmit(sendTyped)
                    .disabled(dialogue.isListening)
                    .accessibilityIdentifier("jarvis-workspace-text-input")

                Button(action: sendTyped) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          dialogue.isListening)
                .accessibilityIdentifier("jarvis-workspace-send")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Text("독립 채팅창 · 코어는 계속 실행됩니다")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.042, blue: 0.055))
        .onDisappear { dialogue.textInputFocused = false }
        .accessibilityIdentifier("jarvis-detached-casual-chat")
    }

    private func sendTyped() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedText = ""
        dialogue.submitTyped(text)
    }
}
