import SwiftUI

/// 대시보드 패널이 "코어 조각으로 조립되듯" 나타나는 효과 (A안 · 모자이크).
///  1) 패널 위치를 JarvisShardAssembly 에 알려 준다 → 코어 조각이 이 자리로 날아와 타일처럼 채운다.
///  2) 조각이 다 내려앉으면(JarvisShardTiming.melt) 패널이 반짝이며 유리처럼 나타난다.
/// 동작 줄이기(접근성) 설정이면 바로 나타난다.
struct JarvisDrawIn: ViewModifier {
    let delay: Double
    let accent: Color
    var corner: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var flash = 0.0

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.975)
            .overlay {
                // 조각이 녹아드는 순간의 반짝임
                RoundedRectangle(cornerRadius: corner)
                    .fill(accent.opacity(0.28 * flash))
                    .overlay(RoundedRectangle(cornerRadius: corner).stroke(accent.opacity(0.9 * flash), lineWidth: 1.4))
                    .shadow(color: accent.opacity(0.7 * flash), radius: 10)
                    .allowsHitTesting(false)
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: JarvisShardTargetsKey.self,
                                           value: [JarvisShardTarget(delay: delay,
                                                                     rect: geo.frame(in: .named("jarvisDash")),
                                                                     accent: accent)])
                }
            }
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                shown = false
                flash = 0
                let melt = JarvisShardTiming.melt(delay)
                withAnimation(.easeOut(duration: JarvisShardTiming.meltDuration).delay(melt)) { shown = true }
                withAnimation(.easeOut(duration: 0.12).delay(melt)) { flash = 1 }
                withAnimation(.easeIn(duration: 0.5).delay(melt + 0.12)) { flash = 0 }
            }
    }
}

extension View {
    /// 패널을 코어 조각으로 조립되듯 나타나게 한다. delay: 대시보드가 열린 뒤 이 패널 차례(초).
    func jarvisDrawIn(delay: Double, accent: Color, corner: CGFloat = 8) -> some View {
        modifier(JarvisDrawIn(delay: delay, accent: accent, corner: corner))
    }
}
