"""AlarmKit user-controlled iPhone JARVIS alarms, independent of Apple Clock."""
from pathlib import Path
import plistlib
import unittest

BASE = Path(__file__).resolve().parents[1]
IOS = BASE / 'ios/JARVIS/Sources'
DOMAIN = (IOS/'JARVISAlarmDomain.swift').read_text()
STORE = (IOS/'JARVISAlarmStore.swift').read_text()
VIEW = (IOS/'JARVISAlarmView.swift').read_text()
HOME = (IOS/'JARVISHomeView.swift').read_text()
PAGES = (IOS/'JARVISMobileDashboardView.swift').read_text()

class AlarmContract(unittest.TestCase):
    def test_alarmkit_authorization_and_system_scheduling(self):
        self.assertIn('import AlarmKit', STORE)
        self.assertIn('requestAuthorization()', STORE)
        self.assertIn('manager.schedule(id: spec.id, configuration: configuration)', STORE)
        self.assertIn('manager.cancel(id: id)', STORE)
        self.assertIn('try manager.alarms', STORE)
        self.assertIn('schedule: schedule', STORE)
        self.assertIn('.fixed(nextDate)', STORE)
        self.assertIn('.weekly(days)', STORE)
        self.assertIn('if #available(iOS 26.0, *)', STORE)
        self.assertIn('guard #available(iOS 26.0, *)', STORE)

    def test_no_fake_save_and_corrupt_file_protection(self):
        self.assertIn('guard readError == nil', STORE)
        self.assertIn('try persist(next)', STORE)
        self.assertIn('records = next', STORE)
        self.assertIn('try JARVISAlarmSystem.isInstalled(spec.id)', STORE)
        self.assertIn('try? await JARVISAlarmSystem.install(before)', STORE)
        self.assertIn('[.atomic, .completeFileProtectionUnlessOpen]', STORE)
        self.assertIn('alarms-v1.json', STORE)
        self.assertIn('try record.validate()', STORE)

    def test_clear_user_navigation(self):
        self.assertIn('case .alarm: "알람"', PAGES)
        self.assertIn('case .alarm: "alarm"', PAGES)
        self.assertIn('JARVISAlarmView(store: alarms)', HOME)
        self.assertIn('quickAction(.alarm)', HOME)
        self.assertIn('JARVISAlarmEditor', VIEW)
        self.assertIn('3분 뒤 시험 알람', VIEW)
        self.assertIn('알람 삭제', VIEW)
        self.assertIn('요일 반복', VIEW)
        self.assertIn('평일', VIEW)

    def test_permission_in_app_plist_and_no_calendar_side_effects(self):
        plist = plistlib.loads((BASE/'ios/JARVIS/Info.plist').read_bytes())
        self.assertIn('NSAlarmKitUsageDescription', plist)
        self.assertTrue(plist['NSAlarmKitUsageDescription'])
        xcode = (BASE/'ios/JARVIS.xcodeproj/project.pbxproj').read_text()
        for src in ['JARVISAlarmDomain.swift','JARVISAlarmStore.swift','JARVISAlarmView.swift']:
            self.assertIn(src, xcode)
        self.assertNotIn('EventKit', STORE)
        self.assertNotIn('EventKit', VIEW)
        self.assertNotIn('UNUserNotificationCenter', STORE)
        self.assertIn('NSBonjourServices', plist)

if __name__ == '__main__':
    unittest.main()
