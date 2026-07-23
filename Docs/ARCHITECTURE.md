# Architecture

BundlePack has two native applications and one shared file-format contract. The
Swift and C# implementations are intentionally independent so each application
can use its platform's native UI and security APIs.

```text
macOS SwiftUI app ─┐
                   ├─ Docs/FORMAT.md ─ .bundlepack files
Windows WinUI app ─┘
```

## Source ownership

- `macOS/BundlePack/App` contains macOS UI state and create/open workflows. Package
  orchestration is separated from input validation, image normalization, ZIP
  commands, and destination naming helpers. File pickers, drag and drop, and
  Finder icon integration are separated from package workflow state transitions.
- `macOS/BundlePack/App/Views` contains the SwiftUI shell, Create and Open screens,
  password-generator sheet, and shared visual components.
- `macOS/BundlePack/Shared` contains the Swift archive, manifest, and encrypted-container implementation.
  ZIP inspection orchestration is separated from low-level entry, path, DEFLATE,
  and CRC validation.
  Encrypted-container operations are separated from binary-header parsing,
  PBKDF2 key derivation, and nonce construction.
- `macOS/BundlePack/ThumbnailExtension` contains the optional Finder thumbnail provider.
- `macOS/Tests` keeps end-to-end orchestration, archive-validation scenarios,
  and reusable smoke-test support in separate Swift sources.
- `Windows/BundlePack.Core` contains the UI-independent C# format implementation.
  Archive orchestration, validation, and ZIP writing are kept in focused partial
  class files so the format checks can evolve without growing one monolithic source.
  Encrypted-container operations and binary-header processing are separated for
  the same reason while retaining one public API.
  Package workflow entry points are likewise separated from filesystem staging
  and stable-snapshot helpers.
- `Windows/BundlePack.Core.Tests` separates the executable test flow, hostile
  archive scenarios, and shared fixture helpers.
- `Windows/BundlePack.Windows` contains the native WinUI 3 application. Create
  and Open workflows keep operation-state partials and display models outside
  the main XAML code-behind files.
- `Windows/BundlePack.Thumbnail` contains the stream-isolated Explorer thumbnail COM server.
- `Windows/BundlePack.Thumbnail.Tests` exercises its icon decoding and 32-bit DIB output on Windows.
- `Windows/Installer` contains per-user x64 and ARM64 Inno Setup definitions.
- `Windows/Scripts` contains optional per-user Windows shell registration tools.
- `Windows/Tests` contains Windows-only shell and installer integration checks.
- `Fixtures/Compatibility/macOS` contains macOS-created fixtures consumed by C# tests.
- `Fixtures/FormatV1.json` contains neutral v1/container constants and the additive v2 animation contract verified by both native test suites.
- `Docs/FORMAT.md` is the normative cross-platform format contract.
- `global.json` pins Windows command-line builds to the .NET 10 SDK family.
- `Scripts` contains repository-wide cleanup, icon generation, and metadata validation tools.
- `Windows/Scripts/Build.ps1` and `Windows/Scripts/Test.ps1` are the standard
  Windows build and verification entry points used by contributors and CI.
- `Windows/Scripts/Package-ReleaseAssets.ps1` creates the versioned Windows
  application archives, installer copies, and checksums used by tag releases.
- `macOS/Scripts/swift-sources.sh` is the source of truth for Swift command-line
  builds and is validated against the Xcode project during tests.
- `macOS/Scripts/verify-app.sh` and `package-artifact.sh` share bundle validation
  and artifact packaging between local builds, CI, and tag releases.

The repository root treats `macOS` and `Windows` as peer platform boundaries.
Each directory owns its native source, projects, scripts, tests, and platform
guide. Shared fixtures, contracts, and repository-wide tooling remain outside
the platform directories.

Repository metadata validation also keeps each platform's minimum supported OS
consistent across its native project, command-line build, and packaging files.

## Compatibility gates

Normal CI keeps pull requests and pushes to `main` lightweight. Windows runs
first and passes its generated fixtures to the single macOS job:

1. macOS runs its smoke tests and opens the checked-in macOS fixtures.
2. Windows runs the core tests, opens the checked-in macOS fixtures, and creates
   unencrypted, encrypted, and Unicode-password Windows fixtures.
3. The macOS job downloads and opens the Windows fixtures before running the
   rest of its smoke suite.

Each platform also creates an encrypted Unicode-password fixture and opens the
other platform's fixture with a canonically equivalent password in the opposite
Unicode composition form.

Pull requests also receive dependency review. A push to `main` additionally
runs CodeQL for C# and Swift; the manual CodeQL builds double as x64 Windows and
universal macOS application compile checks. No application or installer
artifacts are retained. Generated Windows compatibility fixtures expire after
one day.

The `v<version>` tag workflow performs the full release gate. It builds and
tests the macOS universal app, Windows x64/ARM64 apps and thumbnail providers,
builds both Setup executables, installs and uninstalls the x64 installer, and
rejects tags outside the default branch. It also repeats the Windows-to-macOS
compatibility gate, publishes versioned assets to a GitHub prerelease, and
records GitHub provenance attestations for the ZIP and EXE files. CodeQL is not
repeated for release tags because the release commit must already belong to
`main`.

Format changes must update `Docs/FORMAT.md`, both native implementations, the
fixture generators, and the bidirectional tests in the same pull request. A new
incompatible layout requires a new container or manifest version.

Static packages retain manifest version 1. Selecting an animated GIF writes a
version 2 manifest and stores `animation.gif` inside the ZIP. The public
`icon.png` contract and encrypted-container version remain unchanged, so Finder,
Quick Look, and Explorer continue to use a bounded static image. Only the app's
validated Open view consumes animation bytes; encrypted animation bytes are not
available until unlock.

## Security boundaries

Readers validate paths, normalized path collisions, entry counts, declared and
actual sizes, and manifest-to-payload agreement. Metadata integrity is checked
before package information is displayed, and payload integrity is checked
before extraction. Extraction is bound to the reviewed bytes with a digest on
macOS and a private archive snapshot on Windows, so replacing the original file
after review cannot change what is extracted. Encrypted packages additionally
authenticate the container header, public icon, and every encrypted chunk.

BundlePack does not persist passwords or write them to manifests or logs. A
generated password is placed on the clipboard only when the user chooses Copy;
the app clears it after 60 seconds if the clipboard is unchanged.

## Platform integration status

macOS registers the document type and includes an optional Finder thumbnail
extension. The Windows app remains unpackaged internally; per-user Inno Setup
installers register it under **Open with** and register the Explorer thumbnail
COM server without changing the user's default application. PowerShell scripts
provide the same integration for source builds. Installer changes do not require
a change to the `.bundlepack` format.
