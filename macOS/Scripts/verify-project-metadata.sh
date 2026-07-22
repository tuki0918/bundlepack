#!/bin/zsh
set -euo pipefail

MACOS_ROOT="${0:A:h:h}"
REPOSITORY_ROOT="${MACOS_ROOT:h}"
APP_INFO="$MACOS_ROOT/BundlePack/App/Info.plist"
THUMBNAIL_INFO="$MACOS_ROOT/BundlePack/ThumbnailExtension/Info.plist"
WINDOWS_PROPS="$REPOSITORY_ROOT/Windows/Directory.Build.props"
XCODE_PROJECT="$MACOS_ROOT/BundlePack.xcodeproj/project.pbxproj"
source "$MACOS_ROOT/Scripts/swift-sources.sh"

fail() {
  print -u2 -- "Project metadata mismatch: $1"
  exit 1
}

app_version="$(plutil -extract CFBundleShortVersionString raw "$APP_INFO")"
thumbnail_version="$(plutil -extract CFBundleShortVersionString raw "$THUMBNAIL_INFO")"
windows_version="$(xmllint --xpath 'string(/Project/PropertyGroup/VersionPrefix)' "$WINDOWS_PROPS")"
xcode_versions="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "$XCODE_PROJECT" | sort -u)"

[[ "$thumbnail_version" == "$app_version" ]] \
  || fail "the macOS app ($app_version) and thumbnail extension ($thumbnail_version) versions differ"
[[ "$windows_version" == "$app_version" ]] \
  || fail "the macOS ($app_version) and Windows ($windows_version) versions differ"
[[ "$xcode_versions" == "$app_version" ]] \
  || fail "Xcode MARKETING_VERSION values do not all equal $app_version"

app_build="$(plutil -extract CFBundleVersion raw "$APP_INFO")"
thumbnail_build="$(plutil -extract CFBundleVersion raw "$THUMBNAIL_INFO")"
xcode_builds="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "$XCODE_PROJECT" | sort -u)"

[[ "$thumbnail_build" == "$app_build" ]] \
  || fail "the macOS app ($app_build) and thumbnail extension ($thumbnail_build) build numbers differ"
[[ "$xcode_builds" == "$app_build" ]] \
  || fail "Xcode CURRENT_PROJECT_VERSION values do not all equal $app_build"

app_identifier="$(plutil -extract CFBundleIdentifier raw "$APP_INFO")"
thumbnail_identifier="$(plutil -extract CFBundleIdentifier raw "$THUMBNAIL_INFO")"
[[ "$app_identifier" == "com.tuki0918.BundlePack" ]] \
  || fail "unexpected macOS app identifier: $app_identifier"
[[ "$thumbnail_identifier" == "com.tuki0918.BundlePack.Thumbnail" ]] \
  || fail "unexpected thumbnail extension identifier: $thumbnail_identifier"

for source in "${BUNDLEPACK_APP_SOURCES[@]}" "${BUNDLEPACK_THUMBNAIL_SOURCES[@]}"; do
  [[ -f "$source" ]] || fail "configured Swift source does not exist: ${source#$REPOSITORY_ROOT/}"
done

for source in "$MACOS_ROOT"/BundlePack/App/**/*.swift(N) "$MACOS_ROOT"/BundlePack/Shared/*.swift(N); do
  (( ${BUNDLEPACK_APP_SOURCES[(Ie)$source]} )) \
    || fail "macOS app source is not registered: ${source#$REPOSITORY_ROOT/}"
done

for source in "$MACOS_ROOT"/BundlePack/ThumbnailExtension/*.swift(N); do
  (( ${BUNDLEPACK_THUMBNAIL_SOURCES[(Ie)$source]} )) \
    || fail "thumbnail source is not registered: ${source#$REPOSITORY_ROOT/}"
done

xcode_project_contents="$(<"$XCODE_PROJECT")"
for source in "${BUNDLEPACK_APP_SOURCES[@]}" "${BUNDLEPACK_THUMBNAIL_SOURCES[@]}"; do
  file_name="${source:t}"
  [[ "$xcode_project_contents" == *"path = $file_name;"* ]] \
    || fail "macOS source is missing from Xcode: ${source#$REPOSITORY_ROOT/}"
done

print -- "PASS: project metadata and Swift source registrations are synchronized"
