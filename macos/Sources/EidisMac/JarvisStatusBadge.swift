import SwiftUI

struct JarvisStatusBadge: View {
    enum State {
        case verified
        case pending
        case unavailable
    }
    let label: String
    let value: String
    let state: State

    private var indicator: Color {
        switch state {
        case .verified: Color(red: 0.25, green: 0.83, blue: 0.80)
        case .pending: Color(red: 0.72, green: 0.73, blue: 0.78)
        case .unavailable: Color(red: 0.92, green: 0.58, blue: 0.40)
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(indicator)
                .frame(width: 6, height: 6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.56))
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.89))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color(red: 0.065, green: 0.092, blue: 0.12),
            in: Capsule()
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.65))
        .accessibilityElement(children: .combine)
    }
}
