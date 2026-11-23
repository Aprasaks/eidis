"""JARVIS AlarmKit custom 'I'm awake' action: stop then confirm; keep iOS stop fallback."""
import plistlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / 'ios/JARVIS/Sources'
STORE = (IOS/'JARVISAlarmStore.swift').read_text()
INTENT = (IOS/'JARVISWakeConfirmationIntent.swift').read_text()
HOME = (IOS/'JARVISHomeView.swift').read_text()

class JARVISWakeButtonTests(unittest.TestCase):
    def test_secondary_button_and_intent_wired(self):
        self.assertIn('text: "일어났어"', STORE)
        self.assertIn('systemImageName: "checkmark.circle.fill"', STORE)
        self.assertIn('secondaryButton: awakeButton', STORE)
        self.assertIn('secondaryButtonBehavior: .custom', STORE)
        self.assertIn('secondaryIntent: JARVISWakeConfirmationIntent(alarmID: spec.id.uuidString)', STORE)
        self.assertIn('if #available(iOS 26.1, *)', STORE)
        self.assertIn('AlarmPresentation.Alert(', STORE)
        self.assertIn('import AppIntents', INTENT)
        self.assertIn('LiveActivityIntent', INTENT)

    def test_confirm_requires_successful_stop(self):
        self.assertIn('guard let id = UUID(uuidString: alarmID)', INTENT)
        stop = INTENT.index('try AlarmManager.shared.stop(id: id)')
        record = INTENT.index('defaults.set(Date().timeIntervalSince1970,')
        self.assertLess(stop, record)
        self.assertIn('lastWakeConfirmedAt', INTENT)
        self.assertIn('lastWakeConfirmedID', INTENT)
        self.assertIn('supportedModes: IntentModes = [.background, .foreground(.deferred)]', INTENT)
        self.assertIn('@AppStorage(JARVISWakeConfirmation.timestampKey)', HOME)
        self.assertIn('기상 확인 완료', HOME)

    def test_does_not_replace_core_or_calendar(self):
        xcode = (ROOT/'ios/JARVIS.xcodeproj/project.pbxproj').read_text()
        self.assertIn('JARVISWakeConfirmationIntent.swift', xcode)
        self.assertIn('JARVISCalendarStore.swift', xcode)
        self.assertIn('DECHIVE_Core_Mobile', HOME)
        self.assertIn('quickAction(.alarm)', HOME)
        plist = plistlib.loads((ROOT/'ios/JARVIS/Info.plist').read_bytes())
        self.assertIn('NSAlarmKitUsageDescription', plist)

if __name__ == '__main__':
    unittest.main()
