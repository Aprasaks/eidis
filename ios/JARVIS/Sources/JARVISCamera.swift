@preconcurrency import AVFoundation
import SwiftUI

enum JARVISCameraState: Equatable {
    case idle
    case requesting
    case live
    case unavailable(String)
}

@MainActor
final class JARVISCamera: ObservableObject {
    @Published private(set) var state: JARVISCameraState = .idle
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.dechive.eidis.camera")
    private var configured = false

    var isLive: Bool { state == .live }

    func start() async {
        guard state != .requesting, state != .live else { return }
        #if targetEnvironment(simulator)
        state = .unavailable("시뮬레이터에는 카메라가 없습니다. iPhone에서 직접 실행하세요.")
        return
        #else
        state = .requesting
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                state = .unavailable("카메라 접근이 거절됐습니다. iPhone 설정에서 허용해 주세요.")
                return
            }
        default:
            state = .unavailable("설정 → JARVIS → 카메라에서 권한을 허용해 주세요.")
            return
        }
        let alreadyConfigured = configured
        let result: String? = await withCheckedContinuation { continuation in
            queue.async { [session] in
                if alreadyConfigured {
                    if !session.isRunning { session.startRunning() }
                    continuation.resume(returning: session.isRunning ? nil : "카메라 시작에 실패했습니다.")
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .high
                guard let camera = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: .back
                ) else {
                    session.commitConfiguration()
                    continuation.resume(returning: "후면 카메라를 찾지 못했습니다.")
                    return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        continuation.resume(returning: "카메라 입력을 추가할 수 없습니다.")
                        return
                    }
                    session.addInput(input)
                    session.commitConfiguration()
                    session.startRunning()
                    continuation.resume(returning: session.isRunning ? nil : "카메라 시작에 실패했습니다.")
                } catch {
                    session.commitConfiguration()
                    continuation.resume(returning: "카메라 구성 오류: \(error.localizedDescription)")
                }
            }
        }
        configured = result == nil
        state = result.map { .unavailable($0) } ?? .live
        #endif
    }

    func stop() {
        guard state == .live else { return }
        state = .idle
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

private final class CameraLayerView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var cameraLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct JARVISCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = CameraLayerView()
        view.cameraLayer.session = session
        view.cameraLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
