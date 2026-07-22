#!/bin/zsh

if [[ -z "${MACOS_ROOT:-}" ]]; then
  print -u2 -- "MACOS_ROOT must be set before sourcing swift-sources.sh"
  return 1
fi

BUNDLEPACK_SHARED_SOURCES=(
  "$MACOS_ROOT/BundlePack/Shared/PackageManifest.swift"
  "$MACOS_ROOT/BundlePack/Shared/ZipArchiveInspector.swift"
  "$MACOS_ROOT/BundlePack/Shared/ZipArchiveInspector.Validation.swift"
  "$MACOS_ROOT/BundlePack/Shared/EncryptedContainer.swift"
  "$MACOS_ROOT/BundlePack/Shared/EncryptedContainer.Header.swift"
)

BUNDLEPACK_CORE_SOURCES=(
  "$MACOS_ROOT/BundlePack/App/PackageBuilder.swift"
  "$MACOS_ROOT/BundlePack/App/PackageBuilder.IO.swift"
  "${BUNDLEPACK_SHARED_SOURCES[@]}"
)

BUNDLEPACK_APP_MODEL_SOURCES=(
  "$MACOS_ROOT/BundlePack/App/AppModel.swift"
  "$MACOS_ROOT/BundlePack/App/AppModel.Input.swift"
)

BUNDLEPACK_APP_SOURCES=(
  "$MACOS_ROOT/BundlePack/App/BundlePackApp.swift"
  "${BUNDLEPACK_APP_MODEL_SOURCES[@]}"
  "$MACOS_ROOT/BundlePack/App/Views/ContentView.swift"
  "$MACOS_ROOT/BundlePack/App/Views/CreatePackageView.swift"
  "$MACOS_ROOT/BundlePack/App/Views/PasswordGeneratorSheet.swift"
  "$MACOS_ROOT/BundlePack/App/Views/OpenPackageView.swift"
  "$MACOS_ROOT/BundlePack/App/Views/ViewComponents.swift"
  "$MACOS_ROOT/BundlePack/App/PasswordGenerator.swift"
  "${BUNDLEPACK_CORE_SOURCES[@]}"
)

BUNDLEPACK_THUMBNAIL_SOURCES=(
  "$MACOS_ROOT/BundlePack/ThumbnailExtension/ThumbnailProvider.swift"
  "${BUNDLEPACK_SHARED_SOURCES[@]}"
)
