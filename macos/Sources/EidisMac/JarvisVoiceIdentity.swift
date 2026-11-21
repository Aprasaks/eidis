import AVFoundation
import Foundation
import Darwin

/// Bounded RAM-only buffer for the identical microphone turn sent to local STT.
final class JarvisVoiceIDCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private var bytes = Data()
    private var invalid = false
    private let limit = 16000 * 2 * 120
    init?(source: AVAudioFormat) {
        guard source.sampleRate > 0, source.channelCount > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                         channels: 1, interleaved: true),
              let convert = AVAudioConverter(from: source, to: format) else { return nil }
        converter = convert
        target = format
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !invalid else { return }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength)*16000/buffer.format.sampleRate))+32
        guard let out = AVAudioPCMBuffer(pcmFormat:target,frameCapacity:capacity) else { invalidate();return }
        var sent = false
        var error: NSError?
        let result=converter.convert(to:out,error:&error) { _,state in
            if sent { state.pointee = .noDataNow; return nil }
            sent=true; state.pointee = .haveData; return buffer
        }
        guard result != .error,error == nil else { invalidate();return }
        if out.frameLength == 0 { return }
        let audio=out.audioBufferList.pointee.mBuffers
        let count=Int(out.frameLength)*2
        guard let pointer=audio.mData, Int(audio.mDataByteSize)>=count,
              bytes.count+count<=limit else { invalidate();return }
        bytes.append(pointer.assumingMemoryBound(to: UInt8.self),count:count)
    }
    private func invalidate() { invalid=true; bytes.removeAll(keepingCapacity:false) }
    func take() -> Data? {
        lock.lock(); defer { lock.unlock() }
        let value=invalid || bytes.isEmpty ? nil : bytes
        invalidate()
        return value
    }
    func discard() {
        lock.lock(); defer { lock.unlock() }
        invalidate()
    }
}

enum JarvisVoiceIdentity {
    static var python: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".jarvis-lab/speaker/venv/bin/python")
    }
    static var worker: URL? { Bundle.main.url(forResource:"voice_gate",withExtension:"py") }
    static func verify(_ bytes: Data) async -> Bool {
        guard !bytes.isEmpty, bytes.count<=16000*2*120, let worker,
              FileManager.default.isExecutableFile(atPath:python.path) else { return false }
        let executable=python
        // All I/O is local RAM pipes. The worker is time-bounded and no audio
        // or vector is written to a file, log, URL or external service.
        return await Task.detached(priority:.userInitiated) {
            let p=Process(), input=Pipe(), output=Pipe()
            p.executableURL=executable
            p.arguments=["-I","-B","-u",worker.path,"command"]
            p.standardInput=input; p.standardOutput=output
            p.standardError=FileHandle.nullDevice
            guard fcntl(input.fileHandleForWriting.fileDescriptor,F_SETNOSIGPIPE,1) != -1 else { return false }
            do { try p.run() } catch { return false }
            let watchdog=DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+25,execute:watchdog)
            defer {
                watchdog.cancel()
                try? input.fileHandleForWriting.close()
                try? output.fileHandleForReading.close()
                if p.isRunning { p.terminate() }
            }
            do {
                try input.fileHandleForWriting.write(contentsOf:bytes)
                try input.fileHandleForWriting.close()
            } catch { return false }
            let data=output.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return p.terminationStatus==0 && data==Data("ACCEPT\n".utf8)
        }.value
    }
}
