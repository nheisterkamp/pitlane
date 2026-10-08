#!/bin/bash
# Builds a signed, notarized "Trackmania Launcher.dmg" in dist/.
#
# One-time setup (needs your Apple Developer account):
#   1. Xcode → Settings → Accounts → your team → Manage Certificates → + → Developer ID Application
#   2. xcrun notarytool store-credentials TMLauncher --apple-id <you> --team-id <TEAMID>
#      (uses an app-specific password from account.apple.com)
#
# Usage: VERSION=1.1.0 scripts/release.sh          (NOTARY_PROFILE defaults to TMLauncher)
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-TMLauncher}"
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [[ -z "$SIGN_ID" ]]; then
  echo "No 'Developer ID Application' certificate found. See the setup steps at the top of this script." >&2
  exit 1
fi
echo "Signing as: $SIGN_ID"

SIGN_ID="$SIGN_ID" scripts/build-app.sh
APP="dist/Trackmania Launcher.app"
DMG="dist/Trackmania Launcher.dmg"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Trackmania Launcher" -srcfolder "$STAGE" -fs APFS -format ULFO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

echo "Notarizing (a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
echo "Done: $DMG"
