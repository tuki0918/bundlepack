#!/bin/zsh
set -euo pipefail

MACOS_ROOT="${0:A:h:h}"
REPOSITORY_ROOT="${MACOS_ROOT:h}"
BUILD_ROOT="${BUNDLEPACK_BUILD_DIR:-$REPOSITORY_ROOT/.build}"
APP="${BUNDLEPACK_APP_PATH:-$BUILD_ROOT/BundlePack.app}"
OUTPUT_ROOT="${BUNDLEPACK_ARTIFACT_DIR:-$BUILD_ROOT/artifacts}"
VERSION="${BUNDLEPACK_ARTIFACT_VERSION:-}"

if [[ ! -d "$APP" ]]; then
  print -u2 -- "BundlePack application was not found: $APP"
  exit 1
fi
if [[ "$VERSION" == */* || "$VERSION" == *\\* ]]; then
  print -u2 -- "Artifact version must not contain a path separator: $VERSION"
  exit 1
fi

archive_name="BundlePack-macOS-universal${VERSION:+-$VERSION}.zip"
archive="$OUTPUT_ROOT/$archive_name"
checksum="$archive.sha256"

mkdir -p "$OUTPUT_ROOT"
rm -f "$archive" "$checksum"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$archive"
unzip -tq "$archive"
(
  cd "$OUTPUT_ROOT"
  shasum -a 256 "$archive_name" > "$archive_name.sha256"
)

print -- "$archive"
print -- "$checksum"
