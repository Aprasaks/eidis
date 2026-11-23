"""Mac app backup housekeeping must work after the user clears old builds."""
import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "macos/scripts/prune-app-backups.py"
SPEC = importlib.util.spec_from_file_location("jarvis_backup_pruner", SCRIPT)
pruner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pruner)


class BackupPrunerContract(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.current = root / "JARVIS.app"
        self.backups = root / "JARVIS-backups"
        self.backups.mkdir()
        self.make_app(self.current, 88)
        self.patches = [
            patch.object(pruner, "ROOT", self.backups),
            patch.object(pruner, "CURRENT", self.current),
            patch.object(pruner, "verified_signed", return_value=True),
        ]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temporary.cleanup()

    @staticmethod
    def make_app(path: Path, build: int, identifier: str = "dev.dechive.eidis") -> None:
        (path / "Contents").mkdir(parents=True)
        (path / "Contents" / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier,
            "CFBundleVersion": str(build),
            "CFBundleShortVersionString": "3.14.14",
        }))

    def test_empty_backups_is_valid_after_cleanup(self):
        _, retained, deletions, protected = pruner.plan(3)
        self.assertEqual((retained, deletions, protected), ([], [], []))
        self.assertTrue(self.current.exists())

    def test_one_available_backup_kept_without_synthesizing_others(self):
        previous = self.backups / "JARVIS-v3.14.13.app"
        self.make_app(previous, 87)
        _, retained, deletions, protected = pruner.plan(3)
        self.assertEqual([item[2] for item in retained], [previous])
        self.assertEqual(deletions, [])
        self.assertEqual(protected, [])
        self.assertTrue(self.current.exists())

    def test_keep_three_newest_and_protect_unrelated_app(self):
        for n in range(80, 85):
            self.make_app(self.backups / f"JARVIS-v{n}.app", n)
        unrelated = self.backups / "SOMEONE-ELSE.app"
        self.make_app(unrelated, 1, identifier="unrelated.app")
        _, retained, deletions, protected = pruner.plan(3)
        self.assertEqual([item[0] for item in retained], [84, 83, 82])
        self.assertEqual([item[0] for item in deletions], [81, 80])
        self.assertEqual(protected[0][0], unrelated)


if __name__ == "__main__":
    unittest.main()
