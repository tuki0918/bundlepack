#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"

rm -rf \
  "$ROOT/.build" \
  "$ROOT/DerivedData" \
  "$ROOT/.vs" \
  "$ROOT/Windows/.vs"

find "$ROOT/Windows" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +
find "$ROOT" -type d -name TestResults -prune -exec rm -rf {} +
find "$ROOT" -type f -name .DS_Store -delete

print -- "Removed BundlePack build output, test results, and Finder metadata."
