# Changelog

All notable changes to BundlePack are documented in this file.

## [0.1.0] - Unreleased

### Added

- GitHub Actions checks for tests, universal builds, signatures, and property lists.
- Cross-platform project metadata consistency checks.
- Repository-wide .NET 10 SDK selection for reproducible Windows builds.
- A scoped cleanup script for generated macOS and Windows build output.
- Developer ID signing and notarization release script.
- Public package-format documentation and security reporting guidance.
- Native Windows implementation using C#, WinUI 3, and Windows App SDK 2.2.
- Cross-platform C# core for package creation, encryption, validation, decryption, and safe extraction.
- Bidirectional macOS/Windows compatibility fixtures and CI checks.
- Bidirectional Unicode password-normalization compatibility fixtures.
- Per-user Windows development scripts and CI coverage for registering and removing `.bundlepack` from **Open with**.
- Stream-isolated Windows Explorer thumbnail provider for encrypted and unencrypted package icons.
- Percentage progress and cancellation controls for long create, unlock, and extraction operations on macOS and Windows.
- Cross-platform coverage for empty folders, zero-byte files, same-name file/folder inputs, and cancellation cleanup.
- Short-lived CI application artifacts for universal macOS, Windows x64, and Windows ARM64 testing.
- Per-user x64 and ARM64 Windows Setup executables that automatically install and remove the application, file association, and Explorer thumbnail provider.

### Changed

- Product identifiers now use the `com.tuki0918` namespace.
- Generated passwords copied to the clipboard expire after 60 seconds when unchanged.
- Creation password fields are cleared after a package is created successfully.
- Finder thumbnail icon reads use a lightweight fast path for standard BundlePack ZIP files.
- Quick Look uses the standard macOS file preview; the custom Preview extension has been removed.
- Windows custom icons now accept common raster images and are normalized to the shared 1024 × 1024 PNG format.
- The Windows executable now embeds the BundlePack application icon.
- Windows content lists now display human-readable file sizes, and macOS unlock fields can reveal or hide the password.
- macOS package icons are rendered into an explicit 1024 × 1024 bitmap so Retina display scaling cannot produce an invalid embedded icon.
- Unencrypted packages are staged in the destination directory before replacement, including when saving to another volume.
- GitHub Actions dependencies are pinned to immutable revisions and monitored by Dependabot.
- CI macOS builds are verification-only; public binary distribution uses the separate signed and notarized release workflow.
- The macOS SwiftUI screens are separated into focused files under `macOS/BundlePack/App/Views`.
- Swift source lists are centralized and checked against the filesystem and Xcode project during tests.
- The Windows archive implementation is separated into orchestration, validation, and ZIP-writing source files.
- Windows encrypted-container operations are separated from binary-header parsing and key-derivation helpers.
- Windows package workflow entry points are separated from filesystem staging and snapshot helpers.
- The Windows Create and Open navigation now uses a centered, clearly selected header control; mouse-wheel scrolling remains available over nested content controls, while the centered Create form highlights separate icon and included-file drop targets and hides password-only guidance in ZIP-compatible mode.
- Windows input and rendering now share Per-Monitor V2 DPI coordinates, keeping drag-and-drop targets and mouse-wheel hit testing aligned at non-100% display scaling.
- Windows Setup stores each Explorer thumbnail provider build in a content-addressed directory, preventing a still-running COM Surrogate process from blocking upgrades or exact-build reinstalls.
- macOS ZIP inspection orchestration is separated from low-level entry and payload validation.
- macOS encrypted-container operations are separated from header parsing and cryptographic helpers.
- macOS package creation and extraction workflows are separated from filesystem and image-processing helpers.
- macOS file-picker, drag-and-drop, and Finder-icon interactions are separated from package workflow state handling.
- Native macOS and Windows sources and guides are organized under peer platform directories, while shared fixtures and repository tooling use neutral top-level directories.
- Native macOS and Windows CI jobs run independently, with bidirectional interoperability enforced by a separate compatibility job.
- macOS and Windows smoke tests are split into focused scenario and support sources, and Windows UI operation state and display models are separated from the main XAML code-behind files.
- Repository metadata checks now verify the minimum supported macOS and Windows versions across project, build, test, and installer declarations.

### Security

- Reject exact, case-insensitive, and Unicode-normalized archive output-path collisions before extraction.
- Verify manifest-to-payload agreement, ZIP CRC values, and actual expanded sizes before extraction.
- Reject invalid package icons and require matching public and encrypted inner icons.
- Sanitize extraction folder names, including Windows-reserved device names.
- Reject unexpected ZIP root entries, multi-disk archives, incomplete central directories, and undeclared trailing data.
- Reject oversized or control-character display metadata consistently on macOS and Windows.
- Validate actual DEFLATE output sizes and CRCs before invoking system extraction tools.
- Bind extraction to the reviewed archive bytes to prevent source-file replacement between review and extraction.
- Reject symbolic links nested inside macOS package directories and fail closed when source enumeration is incomplete.
- Bound source icon file size and decoded dimensions before normalization.
- Keep decrypted macOS temporary archives private and remove them when the app terminates.
- Prevent Windows registration scripts from overwriting or removing registry values they do not own.
