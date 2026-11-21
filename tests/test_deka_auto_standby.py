from pathlib import Path
import unittest
UI=(Path(__file__).resolve().parents[1]/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
class AutomaticStandby(unittest.TestCase):
    def test_persisted_opt_in_on_launch(self):
        self.assertIn('private let dekaPreferenceKey = "jarvis.deka.autoStandby"',UI)
        self.assertIn('UserDefaults.standard.bool(forKey: dekaPreferenceKey)',UI)
        self.assertIn('UserDefaults.standard.set(true, forKey: dekaPreferenceKey)',UI)
        self.assertIn('if !ProcessInfo.processInfo.arguments.contains("--overlay-preview") {\n            startPreferredDeka()',UI)
    def test_manual_opt_out_is_persistent(self):
        self.assertIn('UserDefaults.standard.set(false, forKey: dekaPreferenceKey)',UI)
        self.assertIn('self?.stopDeka(reason)',UI)
    def test_sleep_stops_and_wake_restores_opt_in(self):
        self.assertIn('self.dekaSleeping = true',UI)
        self.assertIn('NSWorkspace.didWakeNotification',UI)
        self.assertIn('self?.startPreferredDeka()',UI)
        self.assertIn('removeObserver(dekaWakeObserver)',UI)
if __name__=="__main__":unittest.main()
