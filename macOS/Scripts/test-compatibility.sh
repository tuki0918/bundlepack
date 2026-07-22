#!/bin/zsh
set -euo pipefail

MACOS_ROOT="${0:A:h:h}"
REPOSITORY_ROOT="${MACOS_ROOT:h}"
TEST_ROOT="${BUNDLEPACK_TEST_DIR:-$REPOSITORY_ROOT/.build/compatibility-tests}"
CACHE="$TEST_ROOT/module-cache"

source "$MACOS_ROOT/Scripts/swift-sources.sh"
"$REPOSITORY_ROOT/Scripts/verify-project-metadata.sh"

mkdir -p "$CACHE"

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

FIXTURE_DIRECTORIES=("$REPOSITORY_ROOT/Fixtures/Compatibility/macOS")
if [[ -n "${BUNDLEPACK_WINDOWS_FIXTURES:-}" ]]; then
  FIXTURE_DIRECTORIES+=("$BUNDLEPACK_WINDOWS_FIXTURES")
fi

"$TEST_ROOT/compatibility-smoke" "${FIXTURE_DIRECTORIES[@]}"
