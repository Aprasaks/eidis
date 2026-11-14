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
final class ScreenObserver: ObservableObject {
    @Published private(set) var preview: NSImage?
    @Published private(set) var status = "화면 캡처가 꺼져 있습니다."
    @Published private(set) var busy = false
    @Published private(set) var recognizedText = ""
    @Published private(set) var recognizedLineCount = 0
    @Published private(set) var questionReply = ""

    func answerQuestion(_ question: String) {
        guard !busy else { return }
        questionReply = LocalScreenInsights.answer(question: question, recognizedText: recognizedText)
    }

    func captureOnce() {
        guard !busy else { return }
        busy = true
        preview = nil
        recognizedText = ""
        recognizedLineCount = 0
        questionReply = ""
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
                // Do not OCR JARVIS's own window; capture the other visible apps.
                let ownApps = shareable.applications.filter {
                    $0.bundleIdentifier == Bundle.main.bundleIdentifier
                }
                let filter = SCContentFilter(display: display,
                                             excludingApplications: ownApps,
                                             exceptingWindows: [])
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
                recognizedText = ""
                recognizedLineCount = 0
                questionReply = ""
                status = "화면 캡처 완료 · Mac에서 글자를 읽고 있습니다."
                do {
                    // Recognition runs off the UI thread. Never stores or uploads the image.
                    let result = try await Task.detached(priority: .userInitiated) {
                        try LocalScreenText.recognize(in: frame)
                    }.value
                    recognizedText = result.text
                    recognizedLineCount = result.lineCount
                    status = result.lineCount > 0
                        ? "로컬 글자 인식 완료 · \(result.lineCount)줄 · 외부 전송 없음."
                        : "캡처 성공 · 인식할 글자를 찾지 못했습니다. 그림이나 도표의 의미는 아직 분석하지 않습니다."
                } catch {
                    status = "화면 캡처 성공 · 로컬 글자 인식 실패: \(error.localizedDescription)"
                }
            } catch {
                preview = nil
                recognizedText = ""
                recognizedLineCount = 0
                questionReply = ""
                status = "화면 확인 실패: \(error.localizedDescription)"
            }
        }
    }

    func clear() {
        preview = nil
        recognizedText = ""
        recognizedLineCount = 0
        questionReply = ""
        status = "캡처 화면과 인식한 글자를 메모리에서 지웠습니다. 파일로 저장하지 않았습니다."
    }
}

struct JarvisWindow: View {
    @StateObject private var voice = JarvisVoiceService()
    @StateObject private var elevenLabs = ElevenLabsVoiceService()
    @StateObject private var vision = ScreenObserver()
    @StateObject private var bridge = JarvisBridge()
    @State private var reloadID = UUID()
    @State private var screenQuestion = "이 화면에서 오류가 있는지 찾아줘"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "circle.hexagongrid")
                    .foregroundStyle(.cyan)
                Text("개인 AI 작업 공간")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
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
                        Button("Mac 목소리 미리 듣기") { voice.preview() }
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

                NativeSpeechPanel(bridge: bridge, voice: voice, elevenLabs: elevenLabs)
                    .tabItem { Label("음성", systemImage: "mic") }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("자비스의 눈 · 수동 캡처 테스트")
                                .font(.headline)
                            Text("버튼을 누른 경우에만 화면을 한 번 캡처하고 글자를 Mac에서 읽습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("화면 캡처 + 글자 읽기") { vision.captureOnce() }
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("로컬 글자 인식 (한국어·영어)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if !vision.recognizedText.isEmpty {
                                Text("\(vision.recognizedLineCount)줄")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button("글자 복사") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(vision.recognizedText, forType: .string)
                            }
                            .disabled(vision.recognizedText.isEmpty || vision.busy)
                        }
                        ScrollView {
                            Text(vision.recognizedText.isEmpty
                                 ? "화면 캡처 후 인식한 글자가 여기에 표시됩니다. 이 기능은 그림이나 화면 전체의 의미를 이해하지 않습니다."
                                 : vision.recognizedText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(vision.recognizedText.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 140)
                        .padding(10)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Text("화면 글자에 질문하기 · 로컬 분석")
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            TextField("예: 이 화면에서 오류가 뭐야?", text: $screenQuestion)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { vision.answerQuestion(screenQuestion) }
                            Button("로컬 답변") { vision.answerQuestion(screenQuestion) }
                                .disabled(vision.recognizedText.isEmpty || vision.busy ||
                                          screenQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("음성으로 듣기") { voice.speak(vision.questionReply) }
                                .disabled(vision.questionReply.isEmpty)
                        }
                        ScrollView {
                            Text(vision.questionReply.isEmpty
                                 ? "인식한 글자를 바탕으로 오류 후보나 관련 문구를 찾아줘요. 화면의 이미지 의미나 원인 진단은 아직 할 수 없어요."
                                 : vision.questionReply)
                                .font(.system(size: 12))
                                .foregroundStyle(vision.questionReply.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 105)
                        .padding(10)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    }
                    Text(vision.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(18)
                .tabItem { Label("화면", systemImage: "eye") }

                AccessibilityPanel()
                    .tabItem { Label("UI 구조", systemImage: "rectangle.on.rectangle") }
                MacReadinessPanel()
                    .tabItem { Label("진단", systemImage: "stethoscope") }
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
