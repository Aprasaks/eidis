import SwiftUI

@main
struct JARVISApp: App {
    var body: some Scene {
        WindowGroup {
            JARVISHomeView()
                .preferredColorScheme(.dark)
                .tint(JARVISPalette.cyan)
        }
    }
}

enum JARVISPalette {
    static let cyan = Color(red: 0.33, green: 0.91, blue: 0.99)
    static let blue = Color(red: 0.16, green: 0.48, blue: 0.99)
    static let night = Color(red: 0.025, green: 0.049, blue: 0.090)
    static let glass = Color(red: 0.09, green: 0.16, blue: 0.23)
}
