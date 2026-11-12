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
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify "$APP"
echo "생성 완료: $APP"
echo "실제 Mac에서 마이크/화면 권한을 직접 승인해야 합니다."
