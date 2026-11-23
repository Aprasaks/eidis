#!/bin/bash
# Build a real macOS app bundle, including required privacy usage descriptions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACKAGE="$ROOT/macos"
APP="$ROOT/dist/JARVIS.app"
INFO="$PACKAGE/Resources/Info.plist"

command -v swift >/dev/null || { echo "Swift가 필요합니다."; exit 1; }
command -v plutil >/dev/null || { echo "macOS에서만 앱 패키징이 가능합니다."; exit 1; }
plutil -lint "$INFO"
swift build --package-path "$PACKAGE" -c debug
BIN="$(swift build --package-path "$PACKAGE" -c debug --show-bin-path)/EidisMac"
test -x "$BIN" || { echo "빌드한 실행 파일을 찾지 못했습니다: $BIN"; exit 1; }

mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/EidisMac"
cp "$INFO" "$APP/Contents/Info.plist"

# Package only the audited server and web entry points. Do not bundle the
# developer's SQLite DB, Python caches, credentials, .env, Git or other files.
RESOURCES="$APP/Contents/Resources"
mkdir -p "$RESOURCES/jarvis" "$RESOURCES/web"
cp "$PACKAGE/Resources/Art/JARVIS.icns" "$RESOURCES/JARVIS.icns"
test -s "$RESOURCES/JARVIS.icns"
# Use the user's original 1920x1080 clip verbatim. The old 720p alpha
# conversion introduced visible edge noise on external ultrawide displays.
cp "$PACKAGE/Resources/Art/DECHIVE_FullHD_Loop.mp4" "$RESOURCES/DECHIVE_FullHD_Loop.mp4"
rm -f "$RESOURCES/JARVIS_FullHD_Loop.mp4"
# Remove only the obsolete generated alpha movie from the owned dist bundle.
# Keep the original alpha source in macos/Resources/Art for rollback.
rm -f "$RESOURCES/JARVIS_Activation_Alpha_HEVC.mov"
cp "$ROOT/app.py" "$RESOURCES/app.py"
cp "$ROOT/tools/wakeword/deka_worker.py" "$RESOURCES/deka_worker.py"
cp "$ROOT/tools/speaker/voice_gate.py" "$RESOURCES/voice_gate.py"
cp "$ROOT/tools/speaker/voice_id.py" "$RESOURCES/voice_id.py"
# Explicit, local Chrome approval probe; never copy a Chrome user profile,
# cookies, accounts or browser databases into the signed app.
CHROME_BRIDGE="$ROOT/tools/chrome-bridge"
if [[ -f "$CHROME_BRIDGE/node_modules/chrome-devtools-mcp/package.json" ]]; then
  rm -rf "$RESOURCES/chrome-bridge"  # Only inside the owned dist bundle.
  mkdir -p "$RESOURCES/chrome-bridge"
  for asset in check.mjs policy.mjs package.json package-lock.json; do
    cp "$CHROME_BRIDGE/$asset" "$RESOURCES/chrome-bridge/$asset"
  done
  /usr/bin/ditto "$CHROME_BRIDGE/node_modules" "$RESOURCES/chrome-bridge/node_modules"
else
  echo "Chrome MCP 의존성이 없습니다. tools/chrome-bridge에서 npm ci --ignore-scripts 실행 필요" >&2
  exit 2
fi
for source in "$ROOT"/jarvis/*.py; do
  cp "$source" "$RESOURCES/jarvis/"
done
for asset in index.html style.css terminal.js app.js; do
  cp "$ROOT/web/$asset" "$RESOURCES/web/$asset"
done
# A developer may have tested the previous build and caused Python to write
# __pycache__ under dist/. Those generated files break the code signature.
# Clean ONLY generated Python bytecode inside the owned dist bundle.
find "$RESOURCES" -type f -name '*.pyc' -delete
find "$RESOURCES" -type d -name '__pycache__' -empty -delete
test -f "$RESOURCES/jarvis/server.py"
test -f "$RESOURCES/web/index.html"
test ! -f "$RESOURCES/.env"
test -z "$(find "$RESOURCES" -type f -name '*.pyc' -print -quit)"

# Stable macOS Keychain authorization requires a stable designated
# requirement. Ad-hoc signing (--sign -) changes cdhash with every build,
# so "Always Allow" on dev.dechive.eidis.elevenlabs cannot persist.
# Sign with a real, valid Apple Development certificate from this Mac.
# Never silently fall back to ad-hoc signing (would reintroduce the prompt).
SIGNING_IDENTITY="${JARVIS_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  MATCHES="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk '/"Apple Development: / { print $2 }')"
  MATCH_COUNT="$(printf '%s\n' "$MATCHES" | /usr/bin/awk 'NF {n++} END {print n+0}')"
  if [[ "$MATCH_COUNT" -ne 1 ]]; then
    echo "오류: 서명용 Apple Development 인증서가 정확히 1개 필요합니다 (현재 $MATCH_COUNT개)." >&2
    echo "다른 인증서가 여러 개면 JARVIS_SIGNING_IDENTITY를 기존 인증서 SHA-1로 지정하세요." >&2
    exit 2
  fi
  SIGNING_IDENTITY="$MATCHES"
fi
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
# A CDHash-only designated requirement means the Keychain will prompt again
# whenever any Swift/resource file changes. Reject such a release here.
DESIGNATED_REQUIREMENT="$(/usr/bin/codesign -dr - "$APP" 2>&1)"
if [[ "$DESIGNATED_REQUIREMENT" != *'anchor apple generic'* ]]; then
  echo "오류: JARVIS가 안정적인 Apple 서명으로 빌드되지 않았습니다." >&2
  exit 2
fi
echo "서명 확인: Apple Development / 안정적인 키체인 앱 식별자"
echo "생성 완료: $APP"
echo "실제 Mac에서 마이크/화면 권한을 직접 승인해야 합니다."
