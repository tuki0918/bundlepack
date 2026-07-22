#!/bin/zsh
set -euo pipefail

REPOSITORY_ROOT="${0:A:h:h}"
MACOS_ROOT="$REPOSITORY_ROOT/macOS"
APP_INFO="$MACOS_ROOT/BundlePack/App/Info.plist"
THUMBNAIL_INFO="$MACOS_ROOT/BundlePack/ThumbnailExtension/Info.plist"
WINDOWS_PROPS="$REPOSITORY_ROOT/Windows/Directory.Build.props"
WINDOWS_APP_PROJECT="$REPOSITORY_ROOT/Windows/BundlePack.Windows/BundlePack.Windows.csproj"
WINDOWS_THUMBNAIL_PROJECT="$REPOSITORY_ROOT/Windows/BundlePack.Thumbnail/BundlePack.Thumbnail.csproj"
WINDOWS_THUMBNAIL_TESTS_PROJECT="$REPOSITORY_ROOT/Windows/BundlePack.Thumbnail.Tests/BundlePack.Thumbnail.Tests.csproj"
WINDOWS_INSTALLER="$REPOSITORY_ROOT/Windows/Installer/BundlePack.Common.iss"
XCODE_PROJECT="$MACOS_ROOT/BundlePack.xcodeproj/project.pbxproj"
MACOS_BUILD_SCRIPT="$MACOS_ROOT/Scripts/build.sh"
MACOS_DEFAULT_ICON="$MACOS_ROOT/BundlePack/Resources/DefaultPackageIcon.png"
WINDOWS_DEFAULT_ICON="$REPOSITORY_ROOT/Windows/BundlePack.Windows/Assets/DefaultPackageIcon.png"
EXPECTED_MACOS_MINIMUM="15.0"
EXPECTED_WINDOWS_MINIMUM="10.0.17763"
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

app_macos_minimum="$(plutil -extract LSMinimumSystemVersion raw "$APP_INFO")"
thumbnail_macos_minimum="$(plutil -extract LSMinimumSystemVersion raw "$THUMBNAIL_INFO")"
xcode_macos_minimums="$(sed -n 's/.*MACOSX_DEPLOYMENT_TARGET = \([^;]*\);/\1/p' "$XCODE_PROJECT" | sort -u)"
build_script_macos_minimums="$(sed -n 's/.*-target "[$]arch-apple-macos\([^"]*\)".*/\1/p' "$MACOS_BUILD_SCRIPT" | sort -u)"

[[ "$app_macos_minimum" == "$EXPECTED_MACOS_MINIMUM" ]] \
  || fail "the macOS app minimum is $app_macos_minimum instead of $EXPECTED_MACOS_MINIMUM"
[[ "$thumbnail_macos_minimum" == "$EXPECTED_MACOS_MINIMUM" ]] \
  || fail "the thumbnail extension minimum is $thumbnail_macos_minimum instead of $EXPECTED_MACOS_MINIMUM"
[[ "$xcode_macos_minimums" == "$EXPECTED_MACOS_MINIMUM" ]] \
  || fail "Xcode MACOSX_DEPLOYMENT_TARGET values do not all equal $EXPECTED_MACOS_MINIMUM"
[[ "$build_script_macos_minimums" == "$EXPECTED_MACOS_MINIMUM" ]] \
  || fail "macOS command-line build targets do not all equal $EXPECTED_MACOS_MINIMUM"

windows_app_minimum="$(xmllint --xpath 'string(/Project/PropertyGroup/TargetPlatformMinVersion)' "$WINDOWS_APP_PROJECT")"
windows_thumbnail_framework="$(xmllint --xpath 'string(/Project/PropertyGroup/TargetFramework)' "$WINDOWS_THUMBNAIL_PROJECT")"
windows_thumbnail_tests_framework="$(xmllint --xpath 'string(/Project/PropertyGroup/TargetFramework)' "$WINDOWS_THUMBNAIL_TESTS_PROJECT")"
windows_installer_minimum="$(sed -n 's/^MinVersion=//p' "$WINDOWS_INSTALLER")"
expected_windows_framework_suffix="windows$EXPECTED_WINDOWS_MINIMUM.0"

[[ "$windows_app_minimum" == "$EXPECTED_WINDOWS_MINIMUM.0" ]] \
  || fail "the Windows app minimum is $windows_app_minimum instead of $EXPECTED_WINDOWS_MINIMUM.0"
[[ "$windows_thumbnail_framework" == *"-$expected_windows_framework_suffix" ]] \
  || fail "the thumbnail provider target framework does not encode Windows $EXPECTED_WINDOWS_MINIMUM.0"
[[ "$windows_thumbnail_tests_framework" == *"-$expected_windows_framework_suffix" ]] \
  || fail "the thumbnail tests target framework does not encode Windows $EXPECTED_WINDOWS_MINIMUM.0"
[[ "$windows_installer_minimum" == "$EXPECTED_WINDOWS_MINIMUM" ]] \
  || fail "the Windows installer minimum is $windows_installer_minimum instead of $EXPECTED_WINDOWS_MINIMUM"

app_identifier="$(plutil -extract CFBundleIdentifier raw "$APP_INFO")"
thumbnail_identifier="$(plutil -extract CFBundleIdentifier raw "$THUMBNAIL_INFO")"
[[ "$app_identifier" == "com.tuki0918.BundlePack" ]] \
  || fail "unexpected macOS app identifier: $app_identifier"
[[ "$thumbnail_identifier" == "com.tuki0918.BundlePack.Thumbnail" ]] \
  || fail "unexpected thumbnail extension identifier: $thumbnail_identifier"

cmp -s "$MACOS_DEFAULT_ICON" "$WINDOWS_DEFAULT_ICON" \
  || fail "the macOS and Windows default package icons differ"

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

print -- "PASS: versions, platform minimums, identifiers, default icons, and Swift source registrations are synchronized"
