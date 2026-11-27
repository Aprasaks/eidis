import SwiftUI
import AVFoundation
import AppKit

/// 블렌더로 렌더한 연출 영상 (tools/blender):
/// - DECHIVE_Core_Form.mp4     : 설계도 선 → 금색 코어 (3초, 마지막 프레임이 코어 루프 첫 프레임과 이어짐)
/// - DECHIVE_Core_Dissolve.mp4 : 코어가 금빛 조각으로 분해 (4초)
/// - DECHIVE_Debris_Loop.mp4   : 분해된 조각이 떠다니는 배경 (8초 반복)
/// 모두 검은 배경이라 .screen 합성으로 검정을 투명처럼 겹친다.
enum JarvisCinematics {
    static func url(_ name: String) -> URL? { Bundle.main.url(forResource: name, withExtension: "mp4") }
    static var form: URL? { url("DECHIVE_Core_Form") }
    static var dissolve: URL? { url("DECHIVE_Core_Dissolve") }
    static var debris: URL? { url("DECHIVE_Debris_Loop") }
}

/// 한 번 재생(끝나면 onFinish) 또는 반복 재생하는 영상 레이어.
struct JarvisCinematicClip: NSViewRepresentable {
    let url: URL
    var loop = false
    var onFinish: (() -> Void)? = nil

    final class Coordinator {
        let player: AVQueuePlayer
        var looper: AVPlayerLooper?
        var observer: NSObjectProtocol?
        init(url: URL, loop: Bool, onFinish: (() -> Void)?) {
            let item = AVPlayerItem(url: url)
            player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            if loop {
                looper = AVPlayerLooper(player: player, templateItem: item)
            } else {
                player.insert(item, after: nil)
                observer = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in onFinish?() }
            }
            player.play()
        }
        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            player.pause()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url, loop: loop, onFinish: onFinish) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: context.coordinator.player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.clear.cgColor
        view.layer = CALayer()
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer?.sublayers?.forEach { $0.frame = view.bounds }
        CATransaction.commit()
    }
}

/// 대시보드 배경: 코어가 금빛 조각으로 분해(1회) → 조각이 은은하게 떠다님(반복).
/// 패널 글씨가 잘 읽히도록 어둡게(.screen, 낮은 불투명도) 깔린다.
struct JarvisDebrisBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dissolved = false

    var body: some View {
        ZStack {
            if !reduceMotion, let debris = JarvisCinematics.debris, dissolved {
                JarvisCinematicClip(url: debris, loop: true)
                    .opacity(0.38)
                    .transition(.opacity)
            }
            if !reduceMotion, !dissolved, let dissolve = JarvisCinematics.dissolve {
                JarvisCinematicClip(url: dissolve) {
                    withAnimation(.easeInOut(duration: 0.6)) { dissolved = true }
                }
                .opacity(0.85)
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if JarvisCinematics.dissolve == nil { dissolved = true } }
    }
}
