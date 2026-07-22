#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
source "$ROOT/Scripts/swift-sources.sh"
BUILD_ROOT="$ROOT/.build/compatibility-fixtures"
CACHE="$BUILD_ROOT/module-cache"
OUTPUT="$ROOT/Tests/Compatibility"

rm -rf "$BUILD_ROOT"
mkdir -p "$CACHE" "$OUTPUT"

xcrun swiftc \
  -module-cache-path "$CACHE" \
  -swift-version 5 \
  -O \
  -parse-as-library \
  -o "$BUILD_ROOT/generator" \
  "$ROOT/Scripts/GenerateCompatibilityFixtures.swift" \
  "${BUNDLEPACK_CORE_SOURCES[@]}" \
  -framework AppKit \
  -framework CryptoKit \
  -framework Security

"$BUILD_ROOT/generator" "$OUTPUT"
