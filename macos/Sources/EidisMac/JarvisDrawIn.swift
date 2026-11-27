import SwiftUI

/// 대시보드 패널이 "그려지듯" 나타나는 효과 (DESIGN / ENGINEER / ARCHIVE — 설계도가 실물이 되는 느낌).
///  1) 테두리 선이 한 바퀴 그어지고
///  2) 내용이 위에서 아래로 스캔되며 드러나고 (경계에 빛나는 선)
///  3) 다 드러나면 임시 선은 사라지고 패널 원래 테두리만 남는다.
/// 동작 줄이기(접근성)를 켠 경우 바로 나타난다.
struct JarvisDrawIn: ViewModifier {
    let delay: Double
    let accent: Color
    var corner: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stroke: CGFloat = 0
    @State private var reveal: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(alignment: .top) {
                GeometryReader { geo in
                    Rectangle().frame(height: geo.size.height * reveal)
                }
            }
            .overlay {
                if reveal < 1 {
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: corner)
                                .trim(from: 0, to: stroke)
                                .stroke(accent.opacity(0.95), lineWidth: 1.4)
                                .shadow(color: accent.opacity(0.8), radius: 4)
                            if reveal > 0 {
                                // 스캔 경계선
                                LinearGradient(colors: [.clear, accent.opacity(0.9), .clear],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(height: 1.5)
                                    .shadow(color: accent, radius: 6)
                                    .offset(y: geo.size.height * reveal)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .onAppear {
                guard !reduceMotion else { stroke = 1; reveal = 1; return }
                stroke = 0
                reveal = 0
                withAnimation(.easeInOut(duration: 0.55).delay(delay)) { stroke = 1 }
                withAnimation(.easeOut(duration: 0.5).delay(delay + 0.4)) { reveal = 1 }
            }
    }
}

extension View {
    /// 패널을 그려지듯 나타나게 한다. delay: 대시보드가 열린 뒤 시작까지 초.
    func jarvisDrawIn(delay: Double, accent: Color, corner: CGFloat = 8) -> some View {
        modifier(JarvisDrawIn(delay: delay, accent: accent, corner: corner))
    }
}
