"""Mac JARVIS runs the tested 9B model after 27B was rejected for memory pressure."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "macos/Sources/EidisMac"
CONFIG = (BASE / "JarvisLocalModelConfiguration.swift").read_text()
PANEL = (BASE / "NativeSpeech.swift").read_text()

class SafeLocalQwen(unittest.TestCase):
    def test_one_model_has_no_27b_fallback(self):
        self.assertIn('defaultModel = "qwen3.5:9b-q4_K_M"', CONFIG)
        self.assertIn('selectedModel: String { defaultModel }', CONFIG)
        self.assertNotIn('"qwen3.8:27b-q4_K_M"', CONFIG)

    def test_every_ollama_caller_uses_same_default(self):
        for name in ("JarvisThinkingCore.swift", "JarvisOverlayConversation.swift",
                     "JarvisWikiSocialStudio.swift", "JarvisLocalModelWarmup.swift",
                     "JarvisResearchVerification.swift", "JarvisLearningMemory.swift"):
            text = (BASE / name).read_text()
            self.assertIn('JarvisLocalModelConfiguration.selectedModel', text, name)
        self.assertIn('object["model"] as? String == selectedModel',
                      (BASE / "JarvisLocalModelWarmup.swift").read_text())

    def test_removed_model_not_selectable(self):
        self.assertIn('Qwen 3.5 9B', PANEL)
        self.assertNotIn('jarvis-ollama-model-selector', PANEL)

if __name__ == "__main__":
    unittest.main()
