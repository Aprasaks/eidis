#!/usr/bin/env python3
"""Conservative JARVIS macOS app backup retention.

Dry run by default. --apply removes only superseded dev.dechive.eidis bundles
under ~/.jarvis-lab/app-backups. Keeps the newest --keep DISTINCT signed
builds, preserving any unrelated/legacy apps. Never touches the installed app,
Git source, settings, knowledge, or user documents.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import plistlib
import shutil
import subprocess
from pathlib import Path

IDENTIFIER = "dev.dechive.eidis"
ROOT = Path.home() / ".jarvis-lab" / "app-backups"   # hidden: not shown as apps
CURRENT = Path.home() / "Applications" / "JARVIS.app"
LOGS = Path.home() / "Library" / "Logs" / "JARVIS" / "maintenance"


def identity(path: Path) -> dict:
    with (path / "Contents" / "Info.plist").open("rb") as file:
        return plistlib.load(file)


def verified_signed(path: Path) -> bool:
    result = subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(path)],
        capture_output=True, text=True, timeout=30,
    )
    return result.returncode == 0


def plan(keep_count: int):
    if ROOT.is_symlink() or not ROOT.is_dir():
        raise RuntimeError("Backup directory missing or symbolic link; stopped.")
    if CURRENT.is_symlink() or not CURRENT.is_dir():
        raise RuntimeError("Current JARVIS app missing or a symlink; stopped.")
    active = identity(CURRENT)
    if active.get("CFBundleIdentifier") != IDENTIFIER:
        raise RuntimeError("Installed app identity is unexpected; stopped.")
    if not verified_signed(CURRENT):
        raise RuntimeError("Installed app signature check failed; stopped.")

    eligible, protected = [], []
    for item in sorted(ROOT.iterdir(), key=lambda p: p.name):
        if item.is_symlink() or not item.is_dir() or item.suffix != ".app":
            protected.append((item, "not a normal .app directory"))
            continue
        try:
            metadata = identity(item)
        except (OSError, ValueError, plistlib.InvalidFileException):
            protected.append((item, "unreadable app metadata"))
            continue
        if metadata.get("CFBundleIdentifier") != IDENTIFIER:
            protected.append((item, "different bundle identifier / legacy app"))
            continue
        try:
            build = int(metadata.get("CFBundleVersion", ""))
        except (ValueError, TypeError):
            protected.append((item, "unrecognized build number"))
            continue
        # Extra duplicate backups of a build can be safely removed.
        eligible.append((build, item.stat().st_mtime, item, metadata.get("CFBundleShortVersionString")))
    eligible.sort(key=lambda x: (x[0], x[1], x[2].name), reverse=True)

    retained = []
    seen = set()
    for entry in eligible:
        build, _, path, _ = entry
        if build not in seen and len(retained) < keep_count:
            if not verified_signed(path):
                raise RuntimeError(f"Newest candidate has bad signature: {path.name}; stopped.")
            retained.append(entry)
            seen.add(build)
    # A newly cleaned installation may have fewer than keep_count backups.
    # Keep every existing distinct valid version; never synthesize old apps.
    available_versions = len({entry[0] for entry in eligible})
    if len(retained) != min(keep_count, available_versions):
        raise RuntimeError("Failed to retain all eligible distinct signed backups; stopped.")
    kept_paths = {entry[2] for entry in retained}
    deletions = [entry for entry in eligible if entry[2] not in kept_paths]
    return active, retained, deletions, protected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--keep", type=int, default=3)
    parser.add_argument("--apply", action="store_true", help="Permanently delete superseded backups")
    args = parser.parse_args()
    if args.keep < 1 or args.keep > 10:
        parser.error("--keep must be 1..10")

    active, retained, deletions, protected = plan(args.keep)
    print(f"Current app: {active['CFBundleShortVersionString']} (not touched)")
    print("Keep backups:", ", ".join(f"{p.name} (v{v})" for _, _, p, v in retained))
    print("Other protected entries:", len(protected))
    for p, reason in protected:
        print(f"  PROTECT: {p.name}: {reason}")
    print("Eligible old backups:", len(deletions))
    print("Mode:", "APPLY" if args.apply else "DRY RUN")
    if not args.apply:
        print("No files removed. Pass --apply only after inspecting this plan.")
        return

    LOGS.mkdir(parents=True, exist_ok=True)
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    report_path = LOGS / f"backup-prune-{timestamp}.json"
    manifest = {
        "timestamp": timestamp,
        "backup_directory": str(ROOT),
        "installed_app": str(CURRENT),
        "installed_version": active.get("CFBundleShortVersionString"),
        "kept": [str(item[2]) for item in retained],
        "other_protected": [{"path": str(p), "reason": reason} for p, reason in protected],
        "to_delete": [str(item[2]) for item in deletions],
        "deleted": [],
    }
    # Save the exact deletion plan before touching app bundles.
    report_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")

    for _, _, entry, _ in deletions:
        # Recheck on EVERY deletion; never resolve another path or follow a symlink.
        if entry.parent != ROOT or not entry.name.startswith("JARVIS") or entry.suffix != ".app":
            raise RuntimeError(f"Unexpected deletion path: {entry}")
        if entry.is_symlink() or not entry.is_dir() or identity(entry).get("CFBundleIdentifier") != IDENTIFIER:
            raise RuntimeError(f"Backup changed while processing: {entry}")
        shutil.rmtree(entry)
        manifest["deleted"].append(str(entry))
        # Persist progress for recoverable audit in the event of interruption.
        report_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")

    final_active, final_kept, final_delete, final_protected = plan(args.keep)
    if final_delete:
        raise RuntimeError(f"{len(final_delete)} old backup apps remain unexpectedly")
    print("DELETED", len(manifest["deleted"]))
    print("REMAINING_BACKUP_VERSIONS", [str(x[3]) for x in final_kept])
    print("OTHER_PROTECTED", len(final_protected))
    print("MANIFEST", report_path)
    print("CURRENT_APP_STILL_VALID", final_active.get("CFBundleShortVersionString"))


if __name__ == "__main__":
    main()
