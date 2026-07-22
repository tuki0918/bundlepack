#!/bin/zsh

if [[ -z "${ROOT:-}" ]]; then
  print -u2 -- "ROOT must be set before sourcing swift-sources.sh"
  return 1
fi

BUNDLEPACK_SHARED_SOURCES=(
  "$ROOT/BundlePack/Shared/PackageManifest.swift"
  "$ROOT/BundlePack/Shared/ZipArchiveInspector.swift"
  "$ROOT/BundlePack/Shared/ZipArchiveInspector.Validation.swift"
  "$ROOT/BundlePack/Shared/EncryptedContainer.swift"
  "$ROOT/BundlePack/Shared/EncryptedContainer.Header.swift"
)

BUNDLEPACK_CORE_SOURCES=(
  "$ROOT/BundlePack/App/PackageBuilder.swift"
  "$ROOT/BundlePack/App/PackageBuilder.IO.swift"
  "${BUNDLEPACK_SHARED_SOURCES[@]}"
)

BUNDLEPACK_APP_MODEL_SOURCES=(
  "$ROOT/BundlePack/App/AppModel.swift"
  "$ROOT/BundlePack/App/AppModel.Input.swift"
)

BUNDLEPACK_APP_SOURCES=(
  "$ROOT/BundlePack/App/BundlePackApp.swift"
  "${BUNDLEPACK_APP_MODEL_SOURCES[@]}"
  "$ROOT/BundlePack/App/Views/ContentView.swift"
  "$ROOT/BundlePack/App/Views/CreatePackageView.swift"
  "$ROOT/BundlePack/App/Views/PasswordGeneratorSheet.swift"
  "$ROOT/BundlePack/App/Views/OpenPackageView.swift"
  "$ROOT/BundlePack/App/Views/ViewComponents.swift"
  "$ROOT/BundlePack/App/PasswordGenerator.swift"
  "${BUNDLEPACK_CORE_SOURCES[@]}"
)

BUNDLEPACK_THUMBNAIL_SOURCES=(
  "$ROOT/BundlePack/ThumbnailExtension/ThumbnailProvider.swift"
  "${BUNDLEPACK_SHARED_SOURCES[@]}"
)
