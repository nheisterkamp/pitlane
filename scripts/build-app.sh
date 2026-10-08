#!/bin/bash
# Builds "Pitlane.app" (arm64, release, stripped) into dist/.
# Usage: scripts/build-app.sh [--install]   (--install copies it to ~/Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Pitlane.app"
VERSION="${VERSION:-1.0.0}"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/TMLauncher"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TMLauncher"
strip -x "$APP/Contents/MacOS/TMLauncher"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pitlane</string>
  <key>CFBundleDisplayName</key><string>Pitlane</string>
  <key>CFBundleIdentifier</key><string>nl.nhsd.pitlane</string>
  <key>CFBundleExecutable</key><string>TMLauncher</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.racing-games</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Hardened runtime always, so local builds behave like notarized ones. SIGN_ID selects a
# Developer ID certificate (scripts/release.sh sets it); the default is ad-hoc.
if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --options runtime --sign - "$APP"
fi
echo "Built $APP ($(du -sh "$APP" | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Pitlane.app" "$HOME/Applications/Trackmania Launcher.app"  # old name
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/Pitlane.app"
fi
