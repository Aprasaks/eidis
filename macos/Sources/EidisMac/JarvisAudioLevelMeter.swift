import AVFoundation
import Foundation

/// A lightweight, non-recording amplitude meter used by the JARVIS gold core.
/// Its single Float32 channel is sampled, never archived or sent elsewhere.
final class JarvisAudioLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLevel = 0.0

    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channel = buffer.floatChannelData?[0],
              buffer.frameLength > 0 else { return }
        let total = Int(buffer.frameLength)
        let strideSize = max(1, total / 96)
        var sum = 0.0
        var count = 0
        for index in stride(from: 0, to: total, by: strideSize) {
            let sample = Double(channel[index])
            sum += sample * sample
            count += 1
        }
        guard count > 0 else { return }
        let rms = sqrt(sum / Double(count))
        let normalized = min(1, max(0, (rms - 0.006) * 9.0))
        lock.lock()
        storedLevel = normalized
        lock.unlock()
    }

    var level: Double {
        lock.lock()
        defer { lock.unlock() }
        return storedLevel
    }

    func reset() {
        lock.lock()
        storedLevel = 0
        lock.unlock()
    }
}
