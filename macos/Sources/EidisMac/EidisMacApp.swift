import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import WebKit

/// Native macOS shell. It does not send screenshots to any AI model or server.
@main
struct EidisMacApp: App {
    var body: some Scene {
        WindowGroup("JARVIS") {
            JarvisWindow()
        }
        .defaultSize(width: 1180, height: 770)
    }
}

@MainActor
final class NativeVoice: ObservableObject {
    private let speaker = AVSpeechSynthesizer()

    func answer() {
        speaker.stopSpeaking(at: .immediate)
        let speech = AVSpeechUtterance(string: "네, 듣고 있습니다.")
        speech.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        speech.rate = 0.48
        speaker.speak(speech)
    }
}

@MainActor
final class ScreenObserver: ObservableObject {
    @Published private(set) var preview: NSImage?
    @Published private(set) var status = "화면 캡처가 꺼져 있습니다."
    @Published private(set) var busy = false

    func captureOnce() {
        guard !busy else { return }
        busy = true
        status = "화면 접근 권한을 확인하고 있습니다."
        Task {
            defer { busy = false }
            do {
                // Only one frame on explicit user action, never a background stream.
                let shareable = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                guard let display = shareable.displays.first else {
                    status = "캡처 가능한 디스플레이가 없습니다."
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = display.width
                configuration.height = display.height
                configuration.showsCursor = true
                let frame = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                preview = NSImage(
                    cgImage: frame,
                    size: NSSize(width: CGFloat(frame.width), height: CGFloat(frame.height))
                )
                status = "화면 1장을 로컬 메모리에서 미리보고 있습니다. AI 분석·업로드 없음."
            } catch {
                preview = nil
                status = "화면 확인 실패: \(error.localizedDescription)"
            }
        }
    }

    func clear() {
        preview = nil
        status = "화면 미리보기를 지웠습니다. 별도 파일은 저장하지 않았습니다."
    }
}

struct JarvisWindow: View {
    @StateObject private var voice = NativeVoice()
    @StateObject private var vision = ScreenObserver()
    @StateObject private var bridge = JarvisBridge()
    @State private var reloadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "circle.hexagongrid")
                    .foregroundStyle(.cyan)
                Text("JARVIS")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("NATIVE LAB")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("v0.3 / 음성·화면 실험 · LLM 미연결")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 15)

            Divider()

            TabView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("로컬 자비스 작업 공간")
                            .font(.headline)
                        Spacer()
                        Button("네, 듣고 있습니다.") { voice.answer() }
                            .help("Mac 자체 한국어 음성 합성 테스트")
                        Button("새로고침") { reloadID = UUID() }
                    }
                    Text("먼저 저장소 루트에서 python3 app.py를 실행하세요. 화면은 127.0.0.1:8765에만 연결됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LocalDashboard(event: bridge.event)
                        .id(reloadID)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)))
                }
                .padding(18)
                .tabItem { Label("자비스", systemImage: "sparkles") }

                NativeSpeechPanel(bridge: bridge)
                    .tabItem { Label("음성", systemImage: "mic") }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("자비스의 눈 · 수동 캡처 테스트")
                                .font(.headline)
                            Text("버튼을 누른 경우에만 첫 번째 디스플레이를 한 번 캡처합니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("화면 1장 확인") { vision.captureOnce() }
                            .disabled(vision.busy)
                        Button("지우기") { vision.clear() }
                            .disabled(vision.busy || vision.preview == nil)
                    }
                    Group {
                        if let preview = vision.preview {
                            Image(nsImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "display")
                                    .font(.system(size: 44, weight: .ultraLight))
                                Text("캡처된 화면 없음")
                                    .font(.title3)
                                Text("스크린샷은 자동으로 저장하거나 AI에 전송하지 않습니다.")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                    Text(vision.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(18)
                .tabItem { Label("화면", systemImage: "eye") }
            }
            .padding(.horizontal, 8)
        }
        .background(Color(red: 0.045, green: 0.064, blue: 0.10))
        .preferredColorScheme(.dark)
    }
}

/// Embeds localhost only, with a bridge for verified native-command replies.
struct LocalDashboard: NSViewRepresentable {
    let event: JarvisVisualEvent?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: URL(string: "http://127.0.0.1:8765")!))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.event = event
        context.coordinator.deliver(to: view)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var event: JarvisVisualEvent?
        private var lastDelivered: UUID?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastDelivered = nil
            deliver(to: webView)
        }

        func deliver(to view: WKWebView) {
            guard !view.isLoading, let event, lastDelivered != event.id else { return }
            guard let data = try? JSONEncoder().encode(event.reply),
                  let json = String(data: data, encoding: .utf8) else { return }
            view.evaluateJavaScript("window.jarvisNativeResult(\(json));") { [weak self] _, error in
                if error == nil { self?.lastDelivered = event.id }
            }
        }
    }
}
