#!/bin/zsh
set -euo pipefail

MACOS_ROOT="${0:A:h:h}"
REPOSITORY_ROOT="${MACOS_ROOT:h}"
source "$MACOS_ROOT/Scripts/swift-sources.sh"
BUILD_ROOT="$REPOSITORY_ROOT/.build/compatibility-fixtures"
CACHE="$BUILD_ROOT/module-cache"
OUTPUT="$MACOS_ROOT/Tests/Compatibility"

rm -rf "$BUILD_ROOT"
mkdir -p "$CACHE" "$OUTPUT"

xcrun swiftc \
  -module-cache-path "$CACHE" \
  -swift-version 5 \
  -O \
  -parse-as-library \
  -o "$BUILD_ROOT/generator" \
  "$MACOS_ROOT/Scripts/GenerateCompatibilityFixtures.swift" \
  "${BUNDLEPACK_CORE_SOURCES[@]}" \
  -framework AppKit \
  -framework CryptoKit \
  -framework Security

"$BUILD_ROOT/generator" "$OUTPUT"
