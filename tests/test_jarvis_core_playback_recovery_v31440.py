"""One real video core; recover AVPlayer stalls without fake animation."""
from pathlib import Path
import unittest

SOURCE=(Path(__file__).resolve().parents[1]/
        'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()

class CorePlaybackRecovery(unittest.TestCase):
    def test_single_persistent_core_keeps_real_video(self):
        self.assertIn('let player = AVQueuePlayer()',SOURCE)
        self.assertIn('private var looper: AVPlayerLooper?',SOURCE)
        self.assertIn('persistentPlayback: corePlayback',SOURCE)
        self.assertIn('AVPlayerItem(url: url)',SOURCE)
        self.assertIn('context.coordinator.playback.attach(surface: view)',SOURCE)

    def test_video_recovers_when_stalled_not_when_hidden(self):
        self.assertIn('healthTimer = Timer.scheduledTimer',SOURCE)
        self.assertIn('private func restorePlaybackIfStalled()',SOURCE)
        self.assertIn('surface.window?.isVisible == true',SOURCE)
        self.assertIn('surface.playerLayer?.isReadyForDisplay == true',SOURCE)
        self.assertIn('CMTimeGetSeconds(player.currentTime())',SOURCE)
        self.assertIn('now.timeIntervalSince(lastHealthyAt) >= 13',SOURCE)
        self.assertIn('surface.playerLayer?.player = nil',SOURCE)
        self.assertIn('looper?.disableLooping()',SOURCE)
        self.assertIn('player.removeAllItems()',SOURCE)
        self.assertIn('now.timeIntervalSince(lastRebuildAt) >= 60',SOURCE)

    def test_stop_timer_on_teardown(self):
        self.assertIn('healthTimer?.invalidate()',SOURCE)
        self.assertIn('if !coordinator.persistent { coordinator.playback.player.pause() }',SOURCE)

if __name__=='__main__':unittest.main()
