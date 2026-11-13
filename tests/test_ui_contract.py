"""DOM contract tests for the redesigned UI. No browser/network dependency."""
from html.parser import HTMLParser
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent

class UIElements(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.variants = []
        self.stylesheets = []
        self.scripts = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.append(a["id"])
        if tag == "button" and "variant" in a.get("class", "").split():
            self.variants.append((a.get("data-theme"), a.get("aria-pressed")))
        if tag == "link" and a.get("rel") == "stylesheet":
            self.stylesheets.append(a.get("href"))
        if tag == "script" and a.get("src"):
            self.scripts.append(a["src"])

class JARVISUIContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = (ROOT / "web" / "index.html").read_text(encoding="utf-8")
        cls.css = (ROOT / "web" / "style.css").read_text(encoding="utf-8")
        cls.js = (ROOT / "web" / "app.js").read_text(encoding="utf-8")
        cls.doc = UIElements()
        cls.doc.feed(cls.html)

    def test_unique_ids(self):
        self.assertEqual(len(self.doc.ids), len(set(self.doc.ids)), "중복 HTML id 금지")

    def test_functional_hooks_remain(self):
        expected = {
            "particles", "ring-visual", "workspace", "workspace-title",
            "state-label", "hero-title", "assistant-reply", "assistant-reply-text",
            "assistant-reply-dismiss", "brain-remote-consent", "brain-consent-wrap", "command-form",
            "command-input", "voice-toggle", "mic-status",
            "dashboard-view", "variants-view", "memories-view", "screen-view",
            "close-workspace", "show-variants", "show-memory", "open-screen",
            "back-from-memory", "back-from-screen",
            "screen-video", "screen-overlay", "start-share", "stop-share",
            "vision-question", "vision-consent", "analyze-screen",
            "vision-status", "vision-result",
            "memories-list", "demo-wake", "demo-dashboard",
            "system-terminal", "terminal-toggle", "terminal-content",
            "terminal-feed", "terminal-clear", "terminal-count", "terminal-connection",
            "design-status", "apply-design", "cancel-design",
        }
        self.assertFalse(expected - set(self.doc.ids), "필수 UI 후크 누락")

    def test_idle_is_minimal(self):
        self.assertIn("무엇을 도와드릴까요?", self.html)
        self.assertNotIn('class="topbar"', self.html)
        self.assertNotIn("LAB v1.", self.html)
        self.assertNotIn('class="brand"', self.html)
        self.assertNotIn('id="core-status"', self.html)
        self.assertNotIn('id="memory-count"', self.html)
        self.assertNotIn('id="live-capabilities"', self.html)
        self.assertNotIn('id="connection-label"', self.html)
        self.assertNotIn('id="activity-feed"', self.html)
        self.assertIn('class="terminal-cursor"', self.html)

    def test_design_previews_have_real_choices(self):
        self.assertEqual(
            {theme for theme, _ in self.doc.variants},
            {"ambient", "nebula", "studio", "polar"},
        )
        self.assertEqual(len(self.doc.variants), 4)
        self.assertTrue(all(pressed == "false" for _, pressed in self.doc.variants))

    def test_local_assets_only(self):
        self.assertEqual(self.doc.stylesheets, ["/style.css"])
        self.assertEqual(self.doc.scripts, ["/terminal.js", "/app.js"])
        self.assertIn("fetch('/api/status'", self.js)
        self.assertIn("fetch('/api/activity'", self.js)
        self.assertIn("textContent", self.js)
        self.assertNotIn("activity-feed", self.html)
        self.assertNotIn("last-response", self.html)
        self.assertIn("data-terminal-filter", self.html)

    def test_responsive_and_low_motion(self):
        self.assertIn("@media(max-width:610px)", self.css)
        self.assertIn("prefers-reduced-motion:reduce", self.css)
        self.assertIn(".theme-polar", self.css)

if __name__ == "__main__":
    unittest.main()
