import Foundation
import AppIntents
import AlarmKit

/// Persist only an explicit "일어났어" action, NOT an ordinary system stop/X.
/// This acknowledgement is separate from the AlarmKit alarm's lifecycle so
/// the future morning greeting can be triggered without guessing wake time.
enum JARVISWakeConfirmation {
    static let timestampKey = "jarvis.alarm.lastWakeConfirmedAt"
    static let alarmIDKey = "jarvis.alarm.lastWakeConfirmedID"
}

@available(iOS 26.0, *)
struct JARVISWakeConfirmationIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "일어났어"
    static var description = IntentDescription("JARVIS 알람을 끄고 기상 확인을 기록합니다.")

    // The stop must work while the app is in the background. When permitted,
    // iOS may bring JARVIS to the foreground afterwards; unlocking is managed
    // by iOS, not bypassed by the app.
    static var supportedModes: IntentModes = [.background, .foreground(.deferred)]

    @Parameter(title: "JARVIS 알람 ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        self.alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else {
            throw JARVISAlarmError.invalid("기상 확인할 알람을 찾을 수 없어요.")
        }
        // The custom AlarmKit secondary action does not replace the system's
        // stop control, so explicitly stop the ringing alarm ourselves.
        try AlarmManager.shared.stop(id: id)

        // Only a successfully stopped alarm is acknowledged as "I'm awake".
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970,
                     forKey: JARVISWakeConfirmation.timestampKey)
        defaults.set(id.uuidString,
                     forKey: JARVISWakeConfirmation.alarmIDKey)
        return .result()
    }
}
