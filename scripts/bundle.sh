#!/bin/bash
#
# Packages the SwiftPM executable into a real .app bundle.
#
# UNUserNotificationCenter requires a bundle identifier and traps without one,
# so notifications only work from a bundled app. This script produces that
# bundle. LSUIElement keeps it out of the Dock.
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Vigil.app"

cd "$ROOT"
swift build -c "$CONFIGURATION" --product vigil

BINARY="$(swift build -c "$CONFIGURATION" --product vigil --show-bin-path)/vigil"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Vigil"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Vigil</string>
    <key>CFBundleDisplayName</key>
    <string>Vigil</string>
    <key>CFBundleIdentifier</key>
    <string>com.lupydev.vigil</string>
    <key>CFBundleExecutable</key>
    <string>Vigil</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Advise-only diagnostics. This app never acts on your machine.</string>
</dict>
PLIST
echo '</plist>' >> "$APP/Contents/Info.plist"

# Ad-hoc signature. Enough for local use; a Developer ID is needed to share it.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run it with:  open $APP"
