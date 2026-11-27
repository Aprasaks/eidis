import UIKit
import UserNotifications

/// 잠금화면 알림 (APNs). 기기 토큰을 받아 두었다가, 인증된 Mac 연결로 등록한다
/// (JARVISMobileNearbyCalendar.registerPushIfNeeded). 알림을 누르면 해당 화면(SNS)을 연다.
final class JARVISPushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let tokenKey = "jarvis.push.deviceToken"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
    }

    // 앱이 열려 있을 때도 배너로 보여준다.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    // 알림을 누르면 자비스의 해당 화면으로 (jarvis://social)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let page = response.notification.request.content.userInfo["page"] as? String ?? "social"
        if page.range(of: "^[a-z]{1,20}$", options: .regularExpression) != nil, let url = URL(string: "jarvis://" + page) {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
        completionHandler()
    }
}
