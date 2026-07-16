#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/.build/BundlePack.app"
RELEASE_ROOT="$ROOT/.build/release"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/BundlePack/App/Info.plist")"
ARCHIVE="$RELEASE_ROOT/BundlePack-$VERSION.zip"

: "${APPLE_SIGNING_IDENTITY:?Set APPLE_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to an xcrun notarytool Keychain profile}"

"$ROOT/Scripts/test.sh"
"$ROOT/Scripts/build.sh"

codesign --force --timestamp --options runtime \
  --sign "$APPLE_SIGNING_IDENTITY" \
  --entitlements "$ROOT/BundlePack/ThumbnailExtension/BundlePackThumbnail.entitlements" \
  "$APP/Contents/PlugIns/BundlePackThumbnail.appex"
codesign --force --timestamp --options runtime \
  --sign "$APPLE_SIGNING_IDENTITY" \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
mkdir -p "$RELEASE_ROOT"
rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP" "$ARCHIVE"

xcrun notarytool submit "$ARCHIVE" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# Recreate the distribution archive so it contains the stapled ticket.
rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
echo "$ARCHIVE"
