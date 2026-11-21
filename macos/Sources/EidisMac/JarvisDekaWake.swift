import AppKit
import AVFoundation
import Foundation
import Darwin

/// Bounded, nonblocking PCM relay. It owns the write handle until stopped.
/// Audio is neither saved nor logged.
final class DekaPCMRelay: @unchecked Sendable {
    private let handle: FileHandle
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let lock = NSLock()
    private var closed = false
    private let onFailure: @Sendable () -> Void
    init?(handle: FileHandle, source: AVAudioFormat, onFailure: @escaping @Sendable () -> Void) {
        guard source.sampleRate > 0, source.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: source, to: target) else { return nil }
        self.handle = handle; self.converter = converter; self.target = target; self.onFailure = onFailure
        let fd = handle.fileDescriptor
        guard fcntl(fd, F_SETNOSIGPIPE, 1) != -1,
              fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { return nil }
    }
    func append(_ input: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16000 / input.format.sampleRate)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { fail(); return }
        var sent = false
        var err: NSError?
        let status = converter.convert(to: out, error: &err) { _, state in
            if sent { state.pointee = .noDataNow; return nil }
            sent = true; state.pointee = .haveData; return input
        }
        guard status != .error, err == nil else { fail(); return }
        guard out.frameLength > 0 else { return }
        let audio = out.audioBufferList.pointee.mBuffers
        guard let bytes = audio.mData else { fail(); return }
        let size = Int(out.frameLength) * 2
        guard Int(audio.mDataByteSize) >= size else { fail(); return }
        let wrote = Darwin.write(handle.fileDescriptor, bytes, size)
        if wrote != size { fail() }
    }
    private func fail() {
        guard !closed else { return }
        closed = true
        try? handle.close()
        onFailure()
    }
    func close() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true; try? handle.close()
    }
}

@MainActor final class JarvisDekaWake: ObservableObject {
    @Published private(set) var armed = false
    @Published private(set) var status = "데카 상시 대기 꺼짐"
    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private var process: Process?
    private var relay: DekaPCMRelay?
    private var input: Pipe?
    private var output: Pipe?
    private var deadline: Task<Void, Never>?
    private var epoch = UUID()
    private var outputBuffer = Data()
    private var ready = false
    var onHit: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private func update(_ value: String) { status = value; onStatus?(value) }
    func start() async {
        guard !armed else { return }
        let id = UUID(); epoch = id; armed = true
        update("데카 호출 준비 중…")
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard epoch == id, armed else { return }
        guard allowed else { fail("데카 마이크 권한 필요"); return }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".jarvis-lab/wakeword")
        let python = JarvisVoiceIdentity.python
        guard FileManager.default.isExecutableFile(atPath: python.path),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("deka_ko_experimental.onnx").path),
              let script = JarvisVoiceIdentity.worker else {
            fail("데카 호출 또는 화자 모델 환경 없음"); return
        }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = python
        child.arguments = ["-I", "-B", "-u", script.path, "wake"]
        child.standardInput = stdin; child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        process = child; input = stdin; output = stdout
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            Task { @MainActor [weak self] in self?.receive(data, id: id) }
        }
        do { try child.run() }
        catch { fail("데카 모델 실행 실패"); return }
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, self.epoch == id, !self.ready else { return }
            self.fail("데카 모델 준비 시간 초과")
        }
    }
    private func receive(_ data: Data, id: UUID) {
        guard epoch == id, armed else { return }
        if data.isEmpty {
            if armed { fail("데카 모델 스트림 종료") }
            return
        }
        outputBuffer.append(data)
        guard outputBuffer.count <= 4096 else { fail("데카 모델 응답 오류"); return }
        while let end = outputBuffer.firstIndex(of: 10) {
            let line = String(decoding: outputBuffer[..<end], as: UTF8.self)
            outputBuffer.removeSubrange(...end)
            if line == "READY", !ready {
                ready = true; startAudio(id: id)
            } else if line == "REJECT", ready {
                NSLog("DEKA: wake candidate rejected by experimental speaker filter")
            } else if line.hasPrefix("HIT "), ready,
                      let score = Double(line.dropFirst(4)), score.isFinite,
                      (0.5...1).contains(score) {
                stop("데카 감지 · \(String(format:"%.2f",score)) · 호출 대기 종료")
                onHit?()
                return
            } else {
                fail("데카 모델 또는 음성 프로필 오류"); return
            }
        }
    }
    private func startAudio(id: UUID) {
        guard epoch == id, armed, let input else { return }
        let node = engine.inputNode
        let source = node.outputFormat(forBus: 0)
        guard let relay = DekaPCMRelay(handle: input.fileHandleForWriting, source: source, onFailure: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.epoch == id else { return }
                self.fail("데카 오디오 전달 오류 · 상시 대기 종료")
            }
        }) else { fail("데카 마이크 변환 실패"); return }
        self.relay = relay
        node.installTap(onBus: 0, bufferSize: 1024, format: source) { buffer,_ in relay.append(buffer) }
        tapInstalled = true
        do { engine.prepare(); try engine.start() }
        catch { fail("데카 마이크 시작 실패"); return }
        update("호출 대기 · 데카")
        deadline?.cancel()
        deadline = nil // only worker startup is time-limited
    }
    private func fail(_ reason: String) {
        stop(reason)
        onFailure?(reason)
    }
    func stop(_ reason: String = "데카 상시 대기 꺼짐") {
        epoch = UUID()
        deadline?.cancel(); deadline = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        relay?.close(); relay = nil
        try? input?.fileHandleForWriting.close()
        output?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
        input = nil; output = nil; process = nil
        outputBuffer.removeAll(); ready = false
        armed = false; update(reason)
    }
}
