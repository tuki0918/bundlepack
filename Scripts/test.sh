#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TEST_ROOT="${BUNDLEPACK_TEST_DIR:-$ROOT/.build/tests}"
CACHE="$TEST_ROOT/module-cache"
ICON="$ROOT/BundlePack/Resources/DefaultPackageIcon.png"

rm -rf "$TEST_ROOT"
mkdir -p "$CACHE"

SHARED_SOURCES=(
  "$ROOT/BundlePack/App/PackageBuilder.swift"
  "$ROOT/BundlePack/Shared/PackageManifest.swift"
  "$ROOT/BundlePack/Shared/ZipArchiveInspector.swift"
  "$ROOT/BundlePack/Shared/EncryptedContainer.swift"
)

xcrun swiftc \
  -module-cache-path "$CACHE" \
  -swift-version 5 \
  -O \
  -parse-as-library \
  -o "$TEST_ROOT/end-to-end-smoke" \
  "$ROOT/Tests/EndToEndSmoke.swift" \
  "${SHARED_SOURCES[@]}" \
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
  "$ROOT/Tests/DragDropSmoke.swift" \
  "$ROOT/BundlePack/App/AppModel.swift" \
  "${SHARED_SOURCES[@]}" \
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
  "$ROOT/Tests/PasswordGeneratorSmoke.swift" \
  "$ROOT/BundlePack/App/PasswordGenerator.swift"

"$TEST_ROOT/password-generator-smoke"

echo "All BundlePack smoke tests passed."
