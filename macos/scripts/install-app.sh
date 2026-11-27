#!/bin/bash
# Install a signed Mac JARVIS release, retaining only the 1 most recent signed prior build
# in a hidden folder (~/.jarvis-lab/app-backups) so extra JARVIS apps never show up in Launchpad/Spotlight.
# Packaging never installs; use --check for a non-mutating audit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/dist/JARVIS.app"
APP="$HOME/Applications/JARVIS.app"
BACKUPS="$HOME/.jarvis-lab/app-backups"
PRUNER="$ROOT/macos/scripts/prune-app-backups.py"
IDENTIFIER="dev.dechive.eidis"

fail() { echo "ERROR: $*" >&2; exit 1; }
value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
verify() {
  [[ -d "$1" && ! -L "$1" ]] || fail "Missing or linked app: $1"
  [[ "$(value "$1" CFBundleIdentifier)" == "$IDENTIFIER" ]] || fail "Unexpected app identifier: $1"
  /usr/bin/codesign --verify --deep --strict "$1" || fail "Invalid signature: $1"
}
[[ $# -eq 0 || ( $# -eq 1 && "$1" == '--check' ) ]] || fail "Usage: $0 [--check]"
[[ -f "$PRUNER" ]] || fail "Backup management script missing"
[[ -d "$SOURCE" && -d "$APP" ]] || fail "Both packaged and installed JARVIS apps must exist"
[[ ! -L "$BACKUPS" ]] || fail "Refusing symbolic backup directory"

verify "$SOURCE"
verify "$APP"
FROM="$(value "$APP" CFBundleShortVersionString)"
TO="$(value "$SOURCE" CFBundleShortVersionString)"
OLD_BUILD="$(value "$APP" CFBundleVersion)"
NEW_BUILD="$(value "$SOURCE" CFBundleVersion)"
[[ "$OLD_BUILD" =~ ^[0-9]+$ && "$NEW_BUILD" =~ ^[0-9]+$ ]] || fail "Non-numeric build version"
echo "Installed JARVIS: $FROM (build $OLD_BUILD)"
echo "Staged JARVIS:    $TO (build $NEW_BUILD)"
if [[ $# -eq 1 ]]; then
  python3 "$PRUNER" --keep 1
  echo "CHECK COMPLETE. No files changed."
  exit 0
fi
(( NEW_BUILD > OLD_BUILD )) || fail "New bundle build must be newer (use --check to audit)"
# 캐러셀 제작 중에 앱을 바꾸면 렌더링·검수를 맡던 앱이 꺼져 제작이 멈춘다 (2026-11-28 01:31).
# 시작한 지 45분 안 된 "running" 실행이 있으면 설치하지 않는다. 급하면 EIDIS_INSTALL_FORCE=1.
if [[ "${EIDIS_INSTALL_FORCE:-0}" != 1 ]] && python3 - <<'PY'
import json, pathlib, sys, time
root = pathlib.Path.home() / ".jarvis-lab/sns-carousel/runs"
for meta in root.glob("*/meta.json"):
    try:
        m = json.loads(meta.read_text())
    except Exception:
        continue
    # startedAt is a Swift Date (seconds since 2001-01-01)
    if m.get("status") == "running" and time.time() - (m.get("startedAt", 0) + 978307200) < 45 * 60:
        print("캐러셀 제작 중: " + meta.parent.name, file=sys.stderr)
        sys.exit(0)
sys.exit(1)
PY
then
  fail "SNS carousel is being made right now; install after it finishes (or EIDIS_INSTALL_FORCE=1)"
fi

mkdir -p "$BACKUPS"
[[ ! -L "$BACKUPS" ]] || fail "Backup directory unexpectedly changed"

# Staging and installed app renames happen on the same filesystem.
STAGE_DIR="$(mktemp -d "$HOME/Applications/.JARVIS-install-XXXXXXXX")"
STAGE="$STAGE_DIR/JARVIS.app"
trap 'if [[ -d "$STAGE_DIR" ]]; then rm -rf "$STAGE_DIR"; fi' EXIT
/usr/bin/ditto "$SOURCE" "$STAGE"
verify "$STAGE"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUPS/JARVIS-v$FROM-$STAMP.app"
[[ ! -e "$BACKUP" ]] || fail "Backup already exists: $BACKUP"

if /usr/bin/pgrep -f "^$APP/Contents/MacOS/EidisMac" >/dev/null; then
  /usr/bin/osascript -e 'tell application id "dev.dechive.eidis" to quit' || true
  for ((i=0; i<30; i++)); do
    /usr/bin/pgrep -f "^$APP/Contents/MacOS/EidisMac" >/dev/null || break
    sleep 0.4
  done
  if /usr/bin/pgrep -f "^$APP/Contents/MacOS/EidisMac" >/dev/null; then
    fail "Running JARVIS did not quit; old app kept."
  fi
fi

mv "$APP" "$BACKUP"
if ! mv "$STAGE" "$APP"; then
  mv "$BACKUP" "$APP"
  fail "Install failed; prior app restored."
fi

if ! /usr/bin/codesign --verify --deep --strict "$APP"; then
  mv "$APP" "$STAGE"
  mv "$BACKUP" "$APP"
  fail "New app signature invalid; prior app restored."
fi

if ! /usr/bin/open -a "$APP"; then
  mv "$APP" "$STAGE"
  mv "$BACKUP" "$APP"
  /usr/bin/open -a "$APP" || true
  fail "New app launch failed; prior app restored."
fi

# Installation completed; old backup pruning is best-effort and audited.
echo "Installed JARVIS v$TO. Pruning old backup apps..."
if ! python3 "$PRUNER" --keep 1 --apply; then
  echo "WARNING: New app installed; backup pruning incomplete. Check logs." >&2
  exit 2
fi
echo "DONE: JARVIS v$TO installed; kept 1 signed previous build."
