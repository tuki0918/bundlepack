#!/bin/zsh
set -euo pipefail

MACOS_ROOT="${0:A:h:h}"
REPOSITORY_ROOT="${MACOS_ROOT:h}"
TEST_ROOT="${BUNDLEPACK_TEST_DIR:-$REPOSITORY_ROOT/.build/tests}"
CACHE="$TEST_ROOT/module-cache"
ICON="$MACOS_ROOT/BundlePack/Resources/DefaultPackageIcon.png"

source "$MACOS_ROOT/Scripts/swift-sources.sh"

rm -rf "$TEST_ROOT"
mkdir -p "$CACHE"

BUNDLEPACK_TEST_DIR="$TEST_ROOT" "$MACOS_ROOT/Scripts/test-compatibility.sh"

xcrun swiftc \
  -module-cache-path "$CACHE" \
  -swift-version 5 \
  -O \
  -parse-as-library \
  -o "$TEST_ROOT/end-to-end-smoke" \
  "$MACOS_ROOT/Tests/EndToEndSmoke.swift" \
  "$MACOS_ROOT/Tests/EndToEndSmoke.ArchiveValidation.swift" \
  "$MACOS_ROOT/Tests/EndToEndSmoke.Support.swift" \
  "${BUNDLEPACK_CORE_SOURCES[@]}" \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  -framework CryptoKit \
  -framework Security

"$TEST_ROOT/end-to-end-smoke" "$ICON"

xcrun swiftc \
  -module-cache-path "$CACHE" \
  -swift-version 5 \
  -O \
  -parse-as-library \
  -o "$TEST_ROOT/drag-drop-smoke" \
  "$MACOS_ROOT/Tests/DragDropSmoke.swift" \
  "${BUNDLEPACK_APP_MODEL_SOURCES[@]}" \
  "${BUNDLEPACK_CORE_SOURCES[@]}" \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  -framework CryptoKit \
  -framework Security

"$TEST_ROOT/drag-drop-smoke" "$ICON"

xcrun swiftc \
  -module-cache-path "$CACHE" \
  -swift-version 5 \
  -O \
  -parse-as-library \
  -o "$TEST_ROOT/password-generator-smoke" \
  "$MACOS_ROOT/Tests/PasswordGeneratorSmoke.swift" \
  "$MACOS_ROOT/BundlePack/App/PasswordGenerator.swift"

"$TEST_ROOT/password-generator-smoke"

echo "All BundlePack smoke tests passed."
