"""JARVIS 3.6 packaged local server policy, no private-data bundling."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SWIFT = (ROOT / "macos/Sources/EidisMac/JarvisBundledServer.swift").read_text()
APP = (ROOT / "macos/Sources/EidisMac/EidisMacApp.swift").read_text()
PACKAGER = (ROOT / "macos/scripts/package-app.sh").read_text()

class BundledServerTests(unittest.TestCase):
    def test_app_starts_only_verified_server_on_launch(self):
        self.assertIn("@NSApplicationDelegateAdaptor(JarvisAppLifecycle.self)", APP)
        self.assertIn("JarvisWindow()", APP)
        self.assertIn(".environmentObject(lifecycle.server)", APP)
        self.assertIn("applicationDidFinishLaunching", SWIFT)
        self.assertIn("await checkHealth()", SWIFT)
        self.assertIn('object["scope"] as? String == "local_read_only"', SWIFT)
        self.assertIn('server["host"] as? String == "127.0.0.1"', SWIFT)
        self.assertIn('server["port"] as? Int == 8765', SWIFT)
        self.assertIn('process.arguments = ["-B", "app.py"]', SWIFT)

    def test_never_terminate_external_service_or_restart_unknowingly(self):
        self.assertIn("private var ownedProcess: Process?", SWIFT)
        self.assertIn("guard let process = ownedProcess else { return }", SWIFT)
        self.assertIn("if process.isRunning {", SWIFT)
        self.assertIn("process.terminate()", SWIFT)
        self.assertNotIn("killall", SWIFT)
        self.assertNotIn("pkill", SWIFT)
        self.assertNotIn("osascript", SWIFT)
        self.assertNotIn("rm -rf", SWIFT)

    def test_no_paid_api_key_or_remote_model_in_bundled_server(self):
        for value in (
            '"OPENAI_API_KEY"', '"ANTHROPIC_API_KEY"',
            '"JARVIS_ENABLE_BRAIN_API"', '"JARVIS_ENABLE_DESIGN_API"',
            '"JARVIS_ENABLE_VISION_API"', '"JARVIS_BRAIN_MODEL"',
            '"JARVIS_DB"'
        ):
            self.assertIn(value, SWIFT)
        self.assertIn("safeEnvironment(from: ProcessInfo.processInfo.environment)", SWIFT)
        self.assertIn('env["JARVIS_NO_BROWSER"] = "1"', SWIFT)

    def test_only_source_and_ui_assets_bundled(self):
        self.assertIn('"$RESOURCES/app.py"', PACKAGER)
        self.assertIn('"$RESOURCES/jarvis/"', PACKAGER)
        self.assertIn('"$RESOURCES/web/$asset"', PACKAGER)
        self.assertIn('test ! -f "$RESOURCES/.env"', PACKAGER)
        self.assertNotIn('memory.sqlite3', PACKAGER)
        self.assertNotIn("cp -R \"$ROOT\"", PACKAGER)

    def test_native_status_replaces_terminal_setup_prompt(self):
        self.assertIn("Text(localServer.message)", APP)
        self.assertIn("await localServer.connectOnLaunch()", APP)
        self.assertIn(".onChange(of: localServer.ready)", APP)
        self.assertNotIn("먼저 저장소 루트에서 python3 app.py를 실행하세요", APP)

if __name__ == "__main__":
    unittest.main()
