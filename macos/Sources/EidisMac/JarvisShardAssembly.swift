import SwiftUI

/// 대시보드 조립 연출 (A안 · 모자이크):
/// 코어가 터진 조각들이 각 패널 자리로 날아가 타일처럼 면을 채우고,
/// 다 채워지면 반짝이며 녹아 유리 같은 패널 한 장이 된다.
///
/// - 패널 위치는 실제 화면에서 받아온다(JarvisShardTargetsKey) → 어떤 화면 크기에서도 정확히 맞는다.
/// - 패널 쪽은 JarvisDrawIn 이 같은 시각표(delay)로 "녹아 나타나기"를 한다.
/// - 동작 줄이기(접근성)를 켜면 그리지 않는다.
struct JarvisShardTarget: Equatable {
    let delay: Double          // 이 패널이 완성되는 시각표 기준 (JarvisDrawIn과 공유)
    let rect: CGRect           // "jarvisDash" 좌표계
    let accent: Color
}

struct JarvisShardTargetsKey: PreferenceKey {
    static var defaultValue: [JarvisShardTarget] = []
    static func reduce(value: inout [JarvisShardTarget], nextValue: () -> [JarvisShardTarget]) {
        value.append(contentsOf: nextValue())
    }
}

enum JarvisShardTiming {
    /// 조각이 출발하는 시각 (패널 delay 기준)
    static func launch(_ delay: Double) -> Double { max(0.05, delay - 0.30) }
    /// 모든 조각이 내려앉는 시각
    static func landed(_ delay: Double) -> Double { delay + 0.50 }
    /// 패널이 유리처럼 나타나기 시작하는 시각 (= 조각이 녹기 시작)
    static func melt(_ delay: Double) -> Double { delay + 0.55 }
    static let meltDuration = 0.45
}

struct JarvisShardAssembly: View {
    let targets: [JarvisShardTarget]
    let origin: CGPoint            // 코어 중심
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let gold = Color(red: 1.0, green: 0.70, blue: 0.32)

    /// 결정적 난수 (프레임마다 같은 조각이 같은 값을 갖도록)
    private static func rnd(_ i: Int, _ k: Int) -> Double {
        let v = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return v - floor(v)
    }

    var body: some View {
        if reduceMotion || targets.isEmpty {
            Color.clear
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(start)
                let end = (targets.map(\.delay).max() ?? 0) + 0.55 + JarvisShardTiming.meltDuration + 0.1
                Canvas { gc, _ in
                    guard t < end else { return }
                    gc.addFilter(.shadow(color: Self.gold.opacity(0.9), radius: 5))
                    var serial = 0
                    for (p, target) in targets.enumerated() {
                        let r = target.rect
                        guard r.width > 4, r.height > 4 else { continue }
                        // 타일 크기: 패널당 약 260개 · 작은 조각으로 (꽉 찬 덩어리처럼 보이지 않게)
                        let side = max(16, sqrt(r.width * r.height / 260))
                        let cols = max(1, Int(ceil(r.width / side))), rows = max(1, Int(ceil(r.height / side)))
                        let tw = r.width / CGFloat(cols), th = r.height / CGFloat(rows)
                        let launch = JarvisShardTiming.launch(target.delay)
                        let landed = JarvisShardTiming.landed(target.delay)
                        let melt = JarvisShardTiming.melt(target.delay)
                        for row in 0..<rows {
                            for col in 0..<cols {
                                serial += 1
                                let i = serial + p * 997
                                // 출발: 코어 주변(반지름 110) · 위쪽 타일부터 조금씩 먼저
                                let a = Self.rnd(i, 1) * 2 * .pi, d = Self.rnd(i, 2) * 110
                                let from = CGPoint(x: origin.x + cos(a) * d, y: origin.y + sin(a) * d)
                                let to = CGPoint(x: r.minX + (CGFloat(col) + 0.5) * tw, y: r.minY + (CGFloat(row) + 0.5) * th)
                                let t0 = launch + Self.rnd(i, 3) * 0.18 + Double(row) / Double(rows) * 0.10
                                let duration = max(0.25, (landed - t0) * (0.75 + Self.rnd(i, 4) * 0.25))
                                guard t >= t0 else { continue }
                                let raw = min(1, (t - t0) / duration)
                                let ease = 1 - pow(1 - raw, 3)
                                // 곡선 경로 (중간에서 옆으로 휘었다가 들어감)
                                let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                                let bend = (Self.rnd(i, 5) - 0.5) * 260
                                let ctrl = CGPoint(x: mid.x - (to.y - from.y) / max(1, hypot(to.x - from.x, to.y - from.y)) * bend,
                                                   y: mid.y + (to.x - from.x) / max(1, hypot(to.x - from.x, to.y - from.y)) * bend)
                                let u = CGFloat(ease)
                                let x = (1 - u) * (1 - u) * from.x + 2 * (1 - u) * u * ctrl.x + u * u * to.x
                                let y = (1 - u) * (1 - u) * from.y + 2 * (1 - u) * u * ctrl.y + u * u * to.y
                                // 밝기: 날아오며 밝아지고, 패널이 나타날 때 한 번 반짝인 뒤 녹아 사라짐
                                var alpha = 0.35 + 0.45 * ease
                                if t > melt {
                                    let m = min(1, (t - melt) / JarvisShardTiming.meltDuration)
                                    alpha = (1 - m) * (0.8 + 0.6 * sin(m * .pi))
                                }
                                guard alpha > 0.01 else { continue }
                                let scale = 0.30 + 0.48 * ease          // 내려앉아도 조각 사이에 틈이 보이게
                                let spin = (1 - ease) * (Self.rnd(i, 6) - 0.5) * 5
                                let w = (tw - 2) * scale, h = (th - 2) * scale
                                var tile = gc
                                tile.translateBy(x: x, y: y)
                                tile.rotate(by: .radians(spin))
                                let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                                let shape = Path(roundedRect: rect, cornerRadius: 2)
                                let tint = Self.rnd(i, 7) < 0.25 ? target.accent : Self.gold
                                tile.fill(shape, with: .color(tint.opacity(alpha * 0.12)))   // 속이 비치는 유리 조각
                                tile.stroke(shape, with: .color(tint.opacity(min(1, alpha) * 0.75)), lineWidth: 0.7)
                            }
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { start = Date() }
        }
    }
}
