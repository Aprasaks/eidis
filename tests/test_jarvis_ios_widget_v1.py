"""아이폰 위젯 계약: App Group 공유, 실제 값만, 위젯 탭 → SNS 화면."""
import pathlib
import unittest

IOS = pathlib.Path(__file__).resolve().parents[1] / "ios"


def read(rel):
    return (IOS / rel).read_text(encoding="utf-8")


class IOSWidget(unittest.TestCase):
    def test_target_and_entitlements(self):
        project = read("JARVIS.xcodeproj/project.pbxproj")
        self.assertIn('productType = "com.apple.product-type.app-extension"', project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = dev.dechive.jarvis.mobile.widget;", project)
        self.assertIn("dstSubfolderSpec = 13;", project)
        self.assertEqual(project.count("JARVISWidgetShared.swift in Sources */,"), 2)
        for f in ("JARVIS/JARVIS.entitlements", "JARVISWidget/JARVISWidget.entitlements"):
            self.assertIn("group.dev.dechive.jarvis.mobile", read(f))
        self.assertIn("com.apple.widgetkit-extension", read("JARVISWidget/Info.plist"))

    def test_real_values_only_and_deep_link(self):
        widget = read("JARVISWidget/JARVISWidget.swift")
        self.assertIn('value.map { $0.formatted() } ?? "—"', widget)
        self.assertIn('URL(string: "jarvis://social")', widget)
        self.assertIn(".accessoryRectangular", widget)
        nearby = read("JARVIS/Sources/JARVISMobileNearbyCalendar.swift")
        self.assertIn("snapshot.widgetSummary.save()", nearby)
        self.assertIn("WidgetCenter.shared.reloadAllTimelines()", nearby)
        self.assertIn('url.scheme == "jarvis", url.host == "social"', read("JARVIS/Sources/JARVISHomeView.swift"))


if __name__ == "__main__":
    unittest.main()
