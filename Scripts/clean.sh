#!/bin/zsh
set -euo pipefail

REPOSITORY_ROOT="${0:A:h:h}"
MACOS_ROOT="$REPOSITORY_ROOT/macOS"

rm -rf \
  "$REPOSITORY_ROOT/.build" \
  "$MACOS_ROOT/DerivedData" \
  "$REPOSITORY_ROOT/.vs" \
  "$REPOSITORY_ROOT/Windows/.vs"

find "$REPOSITORY_ROOT/Windows" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +
find "$REPOSITORY_ROOT" -type d -name TestResults -prune -exec rm -rf {} +
find "$REPOSITORY_ROOT" -type f -name .DS_Store -delete

print -- "Removed BundlePack build output, test results, and Finder metadata."
