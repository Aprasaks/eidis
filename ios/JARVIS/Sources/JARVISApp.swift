import SwiftUI

@main
struct JARVISApp: App {
    // 잠금화면 알림(APNs) 토큰 수신과 알림 탭 처리
    @UIApplicationDelegateAdaptor(JARVISPushAppDelegate.self) private var pushDelegate

    var body: some Scene {
        WindowGroup {
            JARVISHomeView()
                .preferredColorScheme(.dark)
                .tint(JARVISPalette.gold)
        }
    }
}

enum JARVISPalette {
    static let black = Color(red: 0.025, green: 0.029, blue: 0.035)
    static let panel = Color(red: 0.07, green: 0.075, blue: 0.086)
    static let panelEdge = Color(red: 0.19, green: 0.16, blue: 0.12)
    static let gold = Color(red: 1.0, green: 0.66, blue: 0.27)
    static let goldDim = Color(red: 0.64, green: 0.42, blue: 0.19)
    static let white = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let muted = Color(red: 0.57, green: 0.59, blue: 0.62)
}
