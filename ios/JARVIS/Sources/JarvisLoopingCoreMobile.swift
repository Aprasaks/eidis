import AVFoundation
import SwiftUI
import UIKit

/// Mobile crop of the exact 10-second video used by the primary Mac JARVIS overlay.
/// This is intentionally NOT the unrelated SceneKit hologram or a generated mock core.
/// Video is bundled, muted, and looped locally; no network and no microphone capture.
struct JarvisLoopingCoreMobile: UIViewRepresentable {
    let videoURL: URL
    let active: Bool

    final class Coordinator {
        let player = AVQueuePlayer()
        private let looper: AVPlayerLooper

        init(videoURL: URL) {
            player.isMuted = true
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: videoURL))
        }

        deinit { player.pause() }
    }

    final class PlayerSurface: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer {
            // The view's layer class is always AVPlayerLayer.
            layer as! AVPlayerLayer
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(videoURL: videoURL)
    }

    func makeUIView(context: Context) -> PlayerSurface {
        let view = PlayerSurface(frame: .zero)
        view.backgroundColor = .clear
        view.playerLayer.backgroundColor = UIColor.clear.cgColor
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = context.coordinator.player
        if active { context.coordinator.player.play() }
        return view
    }

    func updateUIView(_ view: PlayerSurface, context: Context) {
        view.playerLayer.videoGravity = .resizeAspect
        if active {
            context.coordinator.player.play()
        } else {
            context.coordinator.player.pause()
        }
    }

    static func dismantleUIView(_ view: PlayerSurface, coordinator: Coordinator) {
        coordinator.player.pause()
        view.playerLayer.player = nil
    }
}
