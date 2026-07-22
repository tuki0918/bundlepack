#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_ROOT="${BUNDLEPACK_BUILD_DIR:-$ROOT/.build}"
APP="$BUILD_ROOT/BundlePack.app"
INTERMEDIATES="$BUILD_ROOT/intermediates"

source "$ROOT/Scripts/swift-sources.sh"
rm -rf "$APP" "$INTERMEDIATES"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources" \
  "$APP/Contents/PlugIns/BundlePackThumbnail.appex/Contents/MacOS" \
  "$INTERMEDIATES"

for arch in arm64 x86_64; do
  cache="$INTERMEDIATES/module-cache-$arch"
  mkdir -p "$cache"

  xcrun swiftc \
    -module-cache-path "$cache" \
    -swift-version 5 \
    -O \
    -target "$arch-apple-macos15.0" \
    -parse-as-library \
    -module-name BundlePack \
    -o "$INTERMEDIATES/BundlePack-$arch" \
    "${BUNDLEPACK_APP_SOURCES[@]}" \
    -framework AppKit \
    -framework SwiftUI \
    -framework UniformTypeIdentifiers \
    -framework CryptoKit \
    -framework Security

  xcrun swiftc \
    -module-cache-path "$cache" \
    -swift-version 5 \
    -O \
    -target "$arch-apple-macos15.0" \
    -module-name BundlePackThumbnail \
    -emit-executable \
    -Xlinker -e \
    -Xlinker _NSExtensionMain \
    -o "$INTERMEDIATES/BundlePackThumbnail-$arch" \
    "${BUNDLEPACK_THUMBNAIL_SOURCES[@]}" \
    -framework AppKit \
    -framework QuickLookThumbnailing \
    -framework CryptoKit \
    -framework Security

done

lipo -create \
  "$INTERMEDIATES/BundlePack-arm64" \
  "$INTERMEDIATES/BundlePack-x86_64" \
  -output "$APP/Contents/MacOS/BundlePack"
lipo -create \
  "$INTERMEDIATES/BundlePackThumbnail-arm64" \
  "$INTERMEDIATES/BundlePackThumbnail-x86_64" \
  -output "$APP/Contents/PlugIns/BundlePackThumbnail.appex/Contents/MacOS/BundlePackThumbnail"
cp "$ROOT/BundlePack/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/BundlePack/ThumbnailExtension/Info.plist" \
  "$APP/Contents/PlugIns/BundlePackThumbnail.appex/Contents/Info.plist"
cp "$ROOT/BundlePack/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/BundlePack/Resources/DefaultPackageIcon.png" "$APP/Contents/Resources/DefaultPackageIcon.png"

chmod +x \
  "$APP/Contents/MacOS/BundlePack" \
  "$APP/Contents/PlugIns/BundlePackThumbnail.appex/Contents/MacOS/BundlePackThumbnail"

codesign --force --options runtime --sign - \
  --entitlements "$ROOT/BundlePack/ThumbnailExtension/BundlePackThumbnail.entitlements" \
  "$APP/Contents/PlugIns/BundlePackThumbnail.appex"
codesign --force --options runtime --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "$APP"
