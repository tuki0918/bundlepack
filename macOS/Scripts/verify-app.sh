#!/bin/zsh
set -euo pipefail

MACOS_ROOT="${0:A:h:h}"
REPOSITORY_ROOT="${MACOS_ROOT:h}"
BUILD_ROOT="${BUNDLEPACK_BUILD_DIR:-$REPOSITORY_ROOT/.build}"
APP="${BUNDLEPACK_APP_PATH:-$BUILD_ROOT/BundlePack.app}"

if [[ ! -d "$APP" ]]; then
  print -u2 -- "BundlePack application was not found: $APP"
  exit 1
fi

for binary in \
  "$APP/Contents/MacOS/BundlePack" \
  "$APP/Contents/PlugIns/BundlePackThumbnail.appex/Contents/MacOS/BundlePackThumbnail"
do
  [[ -x "$binary" ]] || {
    print -u2 -- "BundlePack executable was not found: $binary"
    exit 1
  }

  architectures="$(lipo -archs "$binary")"
  [[ "$architectures" == "x86_64 arm64" || "$architectures" == "arm64 x86_64" ]] || {
    print -u2 -- "Unexpected architectures for $binary: $architectures"
    exit 1
  }
done

codesign --verify --deep --strict "$APP"
plutil -lint \
  "$APP/Contents/Info.plist" \
  "$APP/Contents/PlugIns/BundlePackThumbnail.appex/Contents/Info.plist"

print -- "PASS: universal application bundle, signatures, and property lists are valid"
