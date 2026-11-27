import SwiftUI
import AVFoundation
import AppKit

/// 블렌더로 렌더한 연출 영상 (tools/blender):
/// - DECHIVE_Core_Form.mp4     : 설계도 선 → 금색 코어 (3초, 마지막 프레임이 코어 루프 첫 프레임과 이어짐)
/// - DECHIVE_Core_Dissolve.mp4 : 코어가 금빛 조각으로 분해 (4초)
/// - DECHIVE_Debris_Loop.mp4   : 분해된 조각이 떠다니는 배경 (8초 반복)
/// 모두 검은 배경이라 스크린 합성(screenBlendMode)으로 검정을 투명처럼 겹친다.
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
    var screenBlend = false
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

    /// 레이어 크기를 뷰 크기에 맞춰 계속 갱신하는 표면.
    /// (처음 만들 때 크기가 0이라 한 번만 맞추면 영상이 보이지 않았다.)
    final class Surface: NSView {
        let playerLayer: AVPlayerLayer
        init(player: AVPlayer, screenBlend: Bool) {
            playerLayer = AVPlayerLayer(player: player)
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = NSColor.clear.cgColor
            // 검은 배경을 투명처럼: 아래 화면과 '스크린' 합성 (Core Animation 필터)
            if screenBlend { playerLayer.compositingFilter = "screenBlendMode" }
            layer?.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { nil }
        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> Surface {
        Surface(player: context.coordinator.player, screenBlend: screenBlend)
    }

    func updateNSView(_ view: Surface, context: Context) {
        view.needsLayout = true
    }
}
