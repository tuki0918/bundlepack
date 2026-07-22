#!/bin/zsh
set -euo pipefail

REPOSITORY_ROOT="${0:A:h:h}"
MACOS_ROOT="$REPOSITORY_ROOT/macOS"
APP_ICON_RENDERER="$REPOSITORY_ROOT/Scripts/IconGeneration/render-app-icon.swift"
ICNS_BUILDER="$REPOSITORY_ROOT/Scripts/IconGeneration/create-icns.swift"
CACHE="$(mktemp -d "${TMPDIR:-/tmp}/BundlePackIconModuleCache.XXXXXX")"
ICONSET="$CACHE/AppIcon.iconset"
WINDOWS_ASSETS="$REPOSITORY_ROOT/Windows/BundlePack.Windows/Assets"
trap 'rm -rf "$CACHE"' EXIT

mkdir -p "$ICONSET"

render_app_icon_png() {
  local destination="$1"
  local size="$2"
  xcrun swift -module-cache-path "$CACHE" "$APP_ICON_RENDERER" "$destination" "$size"
}

render_app_icon_png "$ICONSET/icon_16x16.png" 16
render_app_icon_png "$ICONSET/icon_16x16@2x.png" 32
render_app_icon_png "$ICONSET/icon_32x32.png" 32
render_app_icon_png "$ICONSET/icon_32x32@2x.png" 64
render_app_icon_png "$ICONSET/icon_128x128.png" 128
render_app_icon_png "$ICONSET/icon_128x128@2x.png" 256
render_app_icon_png "$ICONSET/icon_256x256.png" 256
render_app_icon_png "$ICONSET/icon_256x256@2x.png" 512
render_app_icon_png "$ICONSET/icon_512x512.png" 512
render_app_icon_png "$ICONSET/icon_512x512@2x.png" 1024
xcrun swift -module-cache-path "$CACHE" \
  "$ICNS_BUILDER" \
  "$ICONSET" \
  "$MACOS_ROOT/BundlePack/Resources/AppIcon.icns"
render_app_icon_png "$MACOS_ROOT/BundlePack/Resources/DefaultPackageIcon.png" 1024
mkdir -p "$WINDOWS_ASSETS"
cp \
  "$MACOS_ROOT/BundlePack/Resources/DefaultPackageIcon.png" \
  "$WINDOWS_ASSETS/DefaultPackageIcon.png"
sips -z 256 256 \
  "$MACOS_ROOT/BundlePack/Resources/DefaultPackageIcon.png" \
  --out "$CACHE/AppIcon-256.png" >/dev/null
sips -s format ico \
  "$CACHE/AppIcon-256.png" \
  --out "$WINDOWS_ASSETS/AppIcon.ico" >/dev/null

echo "BundlePack macOS, Windows, and default package icons regenerated."
