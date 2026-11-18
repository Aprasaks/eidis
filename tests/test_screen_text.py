"""Local screenshot text extraction must remain explicit, private, and opt-in."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCREEN = ROOT / "macos/Sources/EidisMac/EidisMacApp.swift"
OCR = ROOT / "macos/Sources/EidisMac/LocalScreenText.swift"


class ScreenTextContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.screen = SCREEN.read_text(encoding="utf-8")
        cls.ocr = OCR.read_text(encoding="utf-8")

    def test_ocr_is_on_device_and_bounded(self):
        self.assertIn("VNRecognizeTextRequest()", self.ocr)
        self.assertIn('request.recognitionLanguages = ["ko-KR", "en-US"]', self.ocr)
        self.assertIn("VNImageRequestHandler(cgImage: image", self.ocr)
        self.assertIn("prefix(12_000)", self.ocr)
        self.assertNotIn("URLSession", self.ocr)
        self.assertNotIn("http://", self.ocr)
        self.assertNotIn("https://", self.ocr)

    def test_one_shot_manual_capture_and_clear(self):
        self.assertIn('Button("화면 캡처 + 글자 읽기") { vision.captureOnce() }', self.screen)
        self.assertIn("SCScreenshotManager.captureImage", self.screen)
        self.assertIn("excludingApplications: ownApps", self.screen)
        self.assertIn("LocalScreenText.recognize(in: frame)", self.screen)
        self.assertIn('Button("글자 복사")', self.screen)
        self.assertIn('Button("지우기") { vision.clear() }', self.screen)
        self.assertIn('recognizedText = ""', self.screen)


    def test_accessibility_is_explicit_and_never_performs_actions(self):
        ax = (ROOT / "macos/Sources/EidisMac/AccessibilityPanel.swift").read_text(encoding="utf-8")
        assert "Button(\"선택 앱 UI 구조 읽기\")" in self.screen
        self.assertIn("uiInspector.inspectSelected()", self.screen)
        self.assertIn("AccessibilityPanel(inspector: uiInspector)", self.screen)
        self.assertIn("uiInspector.selectedPID", self.screen)
        self.assertIn("AccessibilityInspector", ax)
        self.assertIn("AXUIElementCopyAttributeValue", ax)
        # Exactly one AXPress call exists, exclusively in the one-shot
        # refresh path and gated behind an explicit confirmation dialog.
        self.assertEqual(ax.count("AXUIElementPerformAction("), 1)
        self.assertNotIn("AXUIElementSetAttributeValue(", ax)
        self.assertIn("func pressApprovedRefresh(nodeID: UUID)", ax)
        self.assertIn('Button("지금 새로고침 1회 실행")', ax)
        self.assertIn("confirmationDialog", ax)
        self.assertIn("safeRefreshNodes.first(where:", ax)
        self.assertIn("selectedPID == inspectedPID", ax)
        self.assertIn("timeIntervalSince(scannedAt) <= 60", ax)
        self.assertIn("CFEqual(liveWindow, inspectedWindow)", ax)
        self.assertIn("kAXEnabledAttribute", ax)
        self.assertIn("kAXPressAction", ax)

    def test_ui_questions_keep_source_boundaries(self):
        local = (ROOT / "macos/Sources/EidisMac/LocalScreenInsights.swift").read_text(encoding="utf-8")
        self.assertIn("uiElements: [ScreenUIEvidence] = []", local)
        self.assertIn("선택한 앱의 UI 구조 확인 기록이 없어요", local)
        self.assertIn("현재 OCR 화면과 동일한 창인지는", local)
        self.assertIn("safeLine(item.label)", local)
        self.assertNotIn("URLSession", local)


if __name__ == "__main__":
    unittest.main()
