#!/bin/zsh
set -euo pipefail

MACOS_ROOT="${0:A:h:h}"
REPOSITORY_ROOT="${MACOS_ROOT:h}"
TEST_ROOT="${BUNDLEPACK_TEST_DIR:-$REPOSITORY_ROOT/.build/tests}"
CACHE="$TEST_ROOT/module-cache"
ICON="$MACOS_ROOT/BundlePack/Resources/DefaultPackageIcon.png"

source "$MACOS_ROOT/Scripts/swift-sources.sh"
"$MACOS_ROOT/Scripts/verify-project-metadata.sh"

rm -rf "$TEST_ROOT"
mkdir -p "$CACHE"

xcrun swiftc \
  -module-cache-path "$CACHE" \
  -swift-version 5 \
  -O \
  -parse-as-library \
  -o "$TEST_ROOT/end-to-end-smoke" \
  "$MACOS_ROOT/Tests/EndToEndSmoke.swift" \
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
  -o "$TEST_ROOT/compatibility-smoke" \
  "$MACOS_ROOT/Tests/CompatibilitySmoke.swift" \
  "${BUNDLEPACK_CORE_SOURCES[@]}" \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  -framework CryptoKit \
  -framework Security

FIXTURE_DIRECTORIES=("$MACOS_ROOT/Tests/Compatibility")
if [[ -n "${BUNDLEPACK_WINDOWS_FIXTURES:-}" ]]; then
  FIXTURE_DIRECTORIES+=("$BUNDLEPACK_WINDOWS_FIXTURES")
fi
"$TEST_ROOT/compatibility-smoke" "${FIXTURE_DIRECTORIES[@]}"

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
