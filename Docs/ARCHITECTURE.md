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
- `Windows/BundlePack.Core` contains the UI-independent C# format implementation.
  Archive orchestration, validation, and ZIP writing are kept in focused partial
  class files so the format checks can evolve without growing one monolithic source.
  Encrypted-container operations and binary-header processing are separated for
  the same reason while retaining one public API.
  Package workflow entry points are likewise separated from filesystem staging
  and stable-snapshot helpers.
- `Windows/BundlePack.Windows` contains the native WinUI 3 application.
- `Windows/BundlePack.Thumbnail` contains the stream-isolated Explorer thumbnail COM server.
- `Windows/BundlePack.Thumbnail.Tests` exercises its icon decoding and 32-bit DIB output on Windows.
- `Windows/Installer` contains per-user x64 and ARM64 Inno Setup definitions.
- `Windows/Scripts` contains optional per-user Windows shell registration tools.
- `Windows/Tests` contains Windows-only shell and installer integration checks.
- `macOS/Tests/Compatibility` contains macOS-created fixtures consumed by C# tests.
- `Docs/FORMAT.md` is the normative cross-platform format contract.
- `global.json` pins Windows command-line builds to the .NET 10 SDK family.
- `macOS/Scripts/swift-sources.sh` is the source of truth for Swift command-line
  builds and is validated against the Xcode project during tests.

The repository root treats `macOS` and `Windows` as peer platform boundaries.
Each directory owns its native source, projects, scripts, tests, and platform
guide. Shared contracts and repository-wide documentation remain in `Docs`.

## Compatibility gates

The CI workflow performs the following chain:

1. Windows opens the checked-in macOS fixtures.
2. Windows creates unencrypted, encrypted, and Unicode-password fixtures.
3. macOS downloads and opens the Windows fixtures.
4. Both native applications are built on their own operating system.
5. Windows registers the built app for `.bundlepack`, verifies the shell values,
   and removes the temporary per-user registration.
6. Windows renders macOS- and Windows-created packages through the thumbnail
   provider and builds the provider for x64 and ARM64.
7. A separate Windows job builds x64 and ARM64 Setup executables, installs and
   uninstalls x64, and verifies file-association and thumbnail registry cleanup.

Each platform also creates an encrypted Unicode-password fixture and opens the
other platform's fixture with a canonically equivalent password in the opposite
Unicode composition form.

Format changes must update `Docs/FORMAT.md`, both native implementations, the
fixture generators, and the bidirectional tests in the same pull request. A new
incompatible layout requires a new container or manifest version.

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
