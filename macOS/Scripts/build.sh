#!/bin/zsh
set -euo pipefail

MACOS_ROOT="${0:A:h:h}"
REPOSITORY_ROOT="${MACOS_ROOT:h}"
BUILD_ROOT="${BUNDLEPACK_BUILD_DIR:-$REPOSITORY_ROOT/.build}"
APP="$BUILD_ROOT/BundlePack.app"
INTERMEDIATES="$BUILD_ROOT/intermediates"

source "$MACOS_ROOT/Scripts/swift-sources.sh"
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
cp "$MACOS_ROOT/BundlePack/App/Info.plist" "$APP/Contents/Info.plist"
cp "$MACOS_ROOT/BundlePack/ThumbnailExtension/Info.plist" \
  "$APP/Contents/PlugIns/BundlePackThumbnail.appex/Contents/Info.plist"
cp "$MACOS_ROOT/BundlePack/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$MACOS_ROOT/BundlePack/Resources/DefaultPackageIcon.png" "$APP/Contents/Resources/DefaultPackageIcon.png"

chmod +x \
  "$APP/Contents/MacOS/BundlePack" \
  "$APP/Contents/PlugIns/BundlePackThumbnail.appex/Contents/MacOS/BundlePackThumbnail"

codesign --force --options runtime --sign - \
  --entitlements "$MACOS_ROOT/BundlePack/ThumbnailExtension/BundlePackThumbnail.entitlements" \
  "$APP/Contents/PlugIns/BundlePackThumbnail.appex"
codesign --force --options runtime --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "$APP"
