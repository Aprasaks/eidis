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


if __name__ == "__main__":
    unittest.main()
