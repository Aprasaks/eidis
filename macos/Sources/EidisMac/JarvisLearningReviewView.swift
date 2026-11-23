import SwiftUI

/// Compact review controls in the existing KNOWLEDGE dashboard card.
/// No new full-screen page: candidates remain clearly separate from facts.
struct JarvisLearningReviewView: View {
    @ObservedObject var learning: JarvisLearningMemory
    @State private var lastAction = ""

    private let amber = Color(red: 0.94, green: 0.67, blue: 0.30)
    private let muted = Color(red: 0.65, green: 0.69, blue: 0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("대화 학습", systemImage: "brain.head.profile")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(amber)
                Spacer(minLength: 3)
                Button(learning.enabled ? "중지" : "켜기") {
                    Task {
                        lastAction = await learning.respond(to: .enable(!learning.enabled))
                    }
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                .accessibilityIdentifier("jarvis-learning-toggle")
            }
            Text("추출은 선택 사항 · 승인된 기억만 Qwen에 반영")
                .font(.system(size: 9))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("후보 \(learning.pendingCount)건 · 확정 \(learning.approvedCount)건")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.83))
            if learning.pendingCount > 0 {
                ForEach(Array(learning.pending.prefix(3))) { candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("기억 후보 #\(candidate.id) · 검증 전")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(amber)
                        Text(candidate.content)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Button("승인") {
                                Task { lastAction = await learning.respond(to: .approve(candidate.id)) }
                            }
                            .accessibilityIdentifier("jarvis-learning-approve-\(candidate.id)")
                            Button("거절") {
                                Task { lastAction = await learning.respond(to: .reject(candidate.id)) }
                            }
                            .accessibilityIdentifier("jarvis-learning-reject-\(candidate.id)")
                        }
                        .font(.system(size: 9))
                        .buttonStyle(.bordered)
                    }
                    .padding(7)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                }
                if learning.pendingCount > 3 {
                    Text("그 외 후보는 '기억 후보 보여줘'로 조회")
                        .font(.system(size: 9))
                        .foregroundStyle(muted)
                }
            }
            if !learning.approved.isEmpty {
                ForEach(Array(learning.approved.prefix(2))) { record in
                    HStack(alignment: .top, spacing: 4) {
                        Text("✓ #\(record.id)")
                            .foregroundStyle(.green.opacity(0.85))
                        Text(record.content)
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 1)
                    }
                    .font(.system(size: 9))
                }
                Text("수정·삭제: '기억 3번 수정: …' / '기억 3번 삭제'")
                    .font(.system(size: 9))
                    .foregroundStyle(muted)
            }
            if !lastAction.isEmpty {
                Text(lastAction)
                    .font(.system(size: 9))
                    .foregroundStyle(muted)
                    .lineLimit(3)
            }
            Button("기억 새로고침") { Task { await learning.refresh() } }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .foregroundStyle(amber.opacity(0.85))
                .accessibilityIdentifier("jarvis-learning-refresh")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("jarvis-learning-review")
    }
}
