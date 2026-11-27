import SwiftUI

/// 대시보드 패널이 차례대로 부드럽게 나타나는 효과.
/// (코어가 깨지는 모자이크·잔해 연출은 너무 산만해서 2026-11-27 사용자 요청으로 뺐다.)
/// 동작 줄이기(접근성) 설정이면 바로 나타난다.
struct JarvisDrawIn: ViewModifier {
    let delay: Double
    let accent: Color
    var corner: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                shown = false
                withAnimation(.easeOut(duration: 0.35).delay(delay * 0.6)) { shown = true }
            }
    }
}

extension View {
    /// 패널을 차례대로 나타나게 한다. delay: 대시보드가 열린 뒤 이 패널 차례(초).
    func jarvisDrawIn(delay: Double, accent: Color, corner: CGFloat = 8) -> some View {
        modifier(JarvisDrawIn(delay: delay, accent: accent, corner: corner))
    }
}
