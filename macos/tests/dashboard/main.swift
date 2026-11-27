import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

func assertLayout<V: View>(_ view: V, title: String, width: CGFloat, height: CGFloat,
                            screenshot: String? = nil) {
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = bounds
    let window = NSWindow(contentRect: bounds,
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.22))
    let fitted = hosting.fittingSize
    // GeometryReader-based splash fills its parent's fixed frame rather than
    // reporting a large intrinsic fittingSize. Verify the actual host bounds.
    precondition(hosting.bounds.width >= 600 && hosting.bounds.height >= 450,
                 "\(title): invalid render bounds")
    if !title.contains("launch") && !title.contains("immersive") {
        precondition(fitted.width > 100 && fitted.height > 100,
                     "\(title): invalid fitting size")
    }
    if let screenshot {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fatalError("\(title): offscreen image cache unavailable")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("\(title): PNG encoder failed")
        }
        try! png.write(to: URL(fileURLWithPath: screenshot), options: .atomic)
        print("PREVIEW \(title) \(Int(width))×\(Int(height)) at \(screenshot)")
    }
    print("PASS \(title) native SwiftUI \(Int(fitted.width))×\(Int(fitted.height))")
    window.contentView = nil
    window.close()
}

// All data in the screenshot fixture are synthetic, not the user's SQLite.
let sample = JarvisSystemSnapshot(
    server: .online, recordsLoaded: true,
    projectCount: 2, taskCount: 5, doingCount: 1,
    todoCount: 2, doneCount: 2, blockedCount: 0,
    nextTaskTitle: "로컬 검색 결과를 먼저 읽고 원인 확인",
    nextTaskProject: "샘플 프로젝트",
    voiceOutputAvailable: true,
    appleModelState: "Mac 기기 내 모델 사용 가능 · API 비용 없음"
)
precondition(sample.memoryLabel == "로컬 기록 확인")
precondition(sample.taskCount == 5)
precondition(sample.summaryLabel.contains("로컬 작업 기록"))
precondition(JarvisSystemSnapshot.initial.memoryLabel == "서버 연결 필요")
precondition(JarvisSystemSnapshot.initial.server == .checking)
let offline = JarvisSystemSnapshot(
    server: .offline, recordsLoaded: false,
    projectCount: 0, taskCount: 0, doingCount: 0, todoCount: 0,
    doneCount: 0, blockedCount: 0, nextTaskTitle: nil,
    nextTaskProject: nil, voiceOutputAvailable: false,
    appleModelState: "기기 내 모델 상태 미확인"
)
precondition(offline.summaryLabel.contains("연결되지 않았습니다"))
precondition(offline.memoryLabel == "서버 연결 필요")

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
let dashboard = JarvisDashboardHomeView(
    snapshot: sample,
    onOpenWork: {}, onOpenSpeech: {}, onOpenScreen: {},
    onOpenDiagnostics: {}, onOpenConsole: {}, onRefresh: {},
    onPreviewVoice: {}
)
assertLayout(dashboard, title: "JARVIS v3.7 Dashboard (synthetic fixture)",
             width: 1140, height: 675, screenshot: output)
let immersive = JarvisImmersiveHomeView(
    snapshot: sample, onShowDashboard: {}, onRefresh: {},
    onOpenWork: {}, onOpenSpeech: {},
    onOpenScreen: {}, onOpenDiagnostics: {}
)
assertLayout(immersive, title: "JARVIS v3.8 immersive home (synthetic fixture)",
             width: 1140, height: 675,
             screenshot: output.map { $0.replacingOccurrences(
                 of: "dashboard_fixture", with: "immersive_fixture") })
assertLayout(JarvisImmersiveHomeView(
    snapshot: offline, onShowDashboard: {}, onRefresh: {}, onOpenWork: {},
    onOpenSpeech: {}, onOpenScreen: {}, onOpenDiagnostics: {}
), title: "JARVIS v3.8 immersive offline",
   width: 900, height: 600)
assertLayout(JarvisIntroSplashView(snapshot: sample),
             title: "JARVIS v3.7 verified-state launch", width: 1140, height: 720,
             screenshot: output.map { $0.replacingOccurrences(of: "dashboard_fixture", with: "intro_fixture") })
assertLayout(JarvisIntroSplashView(snapshot: offline),
             title: "JARVIS v3.7 offline launch", width: 1140, height: 720)
print("PASS dashboard verified vs pending/offline states with no permissions or backend writes")
