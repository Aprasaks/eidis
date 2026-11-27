"""Regression for iPhone mobile dashboard and truthful data-source boundaries."""
from pathlib import Path
import unittest  # 2026-11-27: 영어 대화·Kokoro Heart 음성으로 갱신 (사용자 요청)

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / 'ios/JARVIS/Sources'


class MobileDashboardContractTests(unittest.TestCase):
    def test_touch_navigation_keeps_original_core_and_input(self):
        home = (IOS / 'JARVISHomeView.swift').read_text()
        self.assertIn('JARVISMobileDashboardView(calendar: calendar, nearby: nearby)', home)
        self.assertIn('JARVISMobileDataPageView(page: selectedPage, calendar: calendar, nearby: nearby)', home)
        self.assertIn('JARVISMobilePage.requestedPage(for: input)', home)
        self.assertIn('ForEach([JARVISMobilePage.core, .dashboard, .alarm, .calendar, .memory])', home)
        self.assertIn('JarvisLoopingCoreMobile(videoURL: videoURL, active: active)', home)
        self.assertIn('voice.speak(page.spokenStatus, for: input)', home)

    def test_mac_data_panels_are_labeled_disconnected(self):
        ui = (IOS / 'JARVISMobileDashboardView.swift').read_text()
        for panel in ['calendar', 'memory', 'stocks', 'projects', 'knowledge', 'social', 'news', 'system']:
            self.assertIn(f'case .{panel}:', ui)
        self.assertIn('연결 준비 중', ui)
        self.assertNotIn('Mac JARVIS 미연결', ui)
        self.assertNotIn('ALL WORKSPACES', ui)
        self.assertNotIn('COMMAND CENTER', ui)

    def test_calendar_is_user_initiated_local_read_only(self):
        source = (IOS / 'JARVISCalendarStore.swift').read_text()
        self.assertNotIn('EventKit', source)
        self.assertIn('calendar-v1.json', source)
        self.assertIn('Data(contentsOf: fileURL)', source)
        self.assertIn('func save(', source)
        self.assertIn('func delete(', source)
        self.assertIn('JARVISCalendarView(store: calendar, nearby: nearby)',
                      (IOS / 'JARVISMobileDashboardView.swift').read_text())
        xcode = (ROOT / 'ios/JARVIS.xcodeproj/project.pbxproj').read_text()
        self.assertEqual(xcode.count('INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription'), 0)

    def test_iphone_only_and_mac_address_not_modified(self):
        self.assertIn('DECHIVE', (IOS / 'JARVISCommand.swift').read_text())
        self.assertIn('JarvisConversationLanguage.summonGreeting',
                      (ROOT / 'macos/Sources/EidisMac/ElevenLabsVoiceService.swift').read_text())


if __name__ == '__main__':
    unittest.main()
