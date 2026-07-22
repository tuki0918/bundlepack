# BundlePack

BundlePack is a native macOS and Windows utility for collecting files and folders into a shareable `.bundlepack` archive. Packages can be created and opened on either platform. They can be encrypted for privacy or stored as standard ZIP-compatible archives. Encryption is enabled by default.

## Highlights

- Add multiple files and folders with a file picker or drag and drop.
- Choose or drop a custom package icon stored with the package.
- Encrypt file names, metadata, ZIP structure, and file contents with AES-256-GCM.
- Create unencrypted `.bundlepack` files that remain compatible with standard ZIP tools.
- Generate strong passwords with configurable length, digit count, and symbol count.
- Open `.bundlepack` files by double-clicking, choosing a file, or dragging one into the app.
- Follow percentage progress and cancel long create, unlock, and extraction operations.
- Display each package's public custom icon in Finder and Windows Explorer thumbnails.
- Exchange encrypted and unencrypted packages between the native SwiftUI macOS app and native WinUI 3 Windows app.
- Run natively on Apple silicon, Intel Macs, x64 Windows, and ARM64 Windows.

## macOS Screenshots

### Initial Views

| Create a new package | Open an existing package |
| --- | --- |
| ![Initial Create screen](Docs/Images/create.png) | ![Initial Open screen](Docs/Images/open.png) |

### Create Workflow

| Filled package details | Built-in password generator |
| --- | --- |
| ![Create screen filled with demo package details, files, a custom icon, and encryption settings](Docs/Images/create-demo.png) | ![Password Generator with configurable length, digits, and symbols](Docs/Images/create-demo-passgen.png) |

The Create screen accepts files, folders, and a custom package icon by drag and drop. Encrypted packages can use a manually entered password or the built-in generator.

### Open Workflow

| Unlock an encrypted package | Review and extract validated contents |
| --- | --- |
| ![Password entry screen for an encrypted BundlePack archive](Docs/Images/unlock.png) | ![Open screen showing validated demo package contents](Docs/Images/open-demo.png) |

## Requirements

### macOS

- macOS 15 or later;
- Xcode with the macOS 15 SDK, or matching Xcode Command Line Tools.

### Windows

- Windows 10 version 1809 or later;
- Visual Studio 2026 with the Windows application development workload;
- .NET 10 SDK.

## Build from Source

### macOS

Clone the repository, then run:

```sh
chmod +x Scripts/*.sh
./Scripts/test.sh
./Scripts/build.sh
```

The app is written to `.build/BundlePack.app`. You can also open `BundlePack.xcodeproj` and build the `BundlePack` scheme in Xcode.

Remove generated macOS and Windows build output and Finder metadata with:

```sh
./Scripts/clean.sh
```

The command-line build uses an ad-hoc signature for local testing. Before distributing the app, sign it with an Apple Developer ID and notarize it.

### Windows

Open `Windows/BundlePack.Windows.sln` in Visual Studio and run the `BundlePack.Windows` project for `x64` or `ARM64`. From a Developer PowerShell prompt:

```powershell
dotnet build .\Windows\BundlePack.Windows.sln -c Release -p:Platform=x64
dotnet build .\Windows\BundlePack.Windows.sln -c Release -p:Platform=ARM64
dotnet run --project .\Windows\BundlePack.Core.Tests -c Release -- --repo . --fixtures .\Tests\Compatibility
```

The Windows client is an unpackaged WinUI app. It supports file pickers, drag
and drop, creation, unlocking, validation, and safe extraction. CI also
builds per-user x64 and ARM64 installers that place the complete application in
a stable location and automatically register **Open with** and Explorer
thumbnails. PowerShell registration scripts remain available for source builds.

Pull requests and pushes are checked on Windows and macOS by GitHub Actions. Windows opens macOS-generated fixtures and creates new Windows fixtures; macOS then opens those Windows-generated files. The workflow also builds the WinUI app, runs the Swift smoke tests, builds universal Intel and Apple Silicon executables, and validates the macOS app bundle.

### CI Test Applications

Every successful [CI workflow run](https://github.com/tuki0918/bundlepack/actions/workflows/ci.yml) provides four downloadable application artifacts for 14 days:

- `BundlePack-macOS-universal-<commit>` contains a ZIP of the universal macOS app and its SHA-256 checksum;
- `BundlePack-Windows-x64-<commit>` contains the x64 app, Explorer thumbnail provider, and optional per-user registration scripts;
- `BundlePack-Windows-arm64-<commit>` contains the corresponding ARM64 files;
- `BundlePack-Windows-Installers-<commit>` contains separate x64 and ARM64 Setup executables plus SHA-256 checksums. The x64 installer is installed and uninstalled by CI; ARM64 execution remains a device-level release check.

Open a workflow run and use its **Artifacts** section to download a build. Choose
`BundlePack-Setup-x64.exe` for Intel/AMD Windows or
`BundlePack-Setup-arm64.exe` for ARM64 Windows. Setup installs for the current
user without an administrator prompt and removes its files and registry entries
through Windows **Installed apps**. The macOS app is ad-hoc signed and not
notarized. The Windows builds and installers are framework-dependent and
unsigned, and the ARM64 build is compiled but not executed by the hosted x64
runner. These artifacts are intended only for short-lived testing and are not
release binaries.

## Releases

Publishing the source repository or a source-only GitHub release does not require an Apple Developer Program membership. Commit the intended changes, push them, and wait for the complete Windows and macOS CI workflow to pass before creating the tag.

Do not publish the locally built `.build/BundlePack.app` as a trusted macOS binary. The command-line build is ad-hoc signed for local use. Public macOS binaries require an active Apple Developer Program membership, a **Developer ID Application** certificate, and successful notarization. An **Apple Development** certificate or a dummy identity is not a substitute.

The Windows app remains unpackaged internally, with an Inno Setup installer for
CI testing. Before publishing a Windows binary, complete the device checks,
bundle or document the required runtimes, and sign the executable, thumbnail
provider, and installer with a trusted code-signing certificate.

See [Docs/RELEASE.md](Docs/RELEASE.md) for the release checklist and the current source-only recommendation.

### Signed macOS Binary

Store notarization credentials in Keychain once:

```sh
xcrun notarytool store-credentials BundlePack
```

Then build, sign, notarize, staple, assess, and package the app with:

```sh
APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="BundlePack" \
./Scripts/release.sh
```

The notarized archive is written to `.build/release/BundlePack-<version>.zip`. Signing credentials and passwords are never read from repository files.

## macOS Finder, Quick Look, and Custom Icons

### Installation

1. Copy `BundlePack.app` to `/Applications`.
2. Launch it once so macOS registers the `.bundlepack` document type.
3. Optionally enable **BundlePack Thumbnail** in **System Settings > General > Login Items & Extensions > Quick Look** to display embedded package icons in Finder.

Keep only one installed copy that uses the same bundle identifier.

### Standard Quick Look

BundlePack intentionally does not ship a custom Quick Look Preview extension. Pressing Space uses macOS's standard file preview instead of a BundlePack-specific content view. This generic document-style presentation is intentional and remains consistent for encrypted and unencrypted packages.

macOS lists Thumbnail extensions under the Quick Look settings. Enabling **BundlePack Thumbnail** only provides package icons to Finder and other thumbnail surfaces; it does not enable a custom content preview. Creating, opening, encrypting, and extracting packages works without the extension.

<img src="Docs/Images/quick-look.png" width="720" alt="Standard macOS Quick Look preview of a BundlePack document">

The extension never displays BundlePack metadata or an internal file list.

### Finder List View

The selected package icon is also shown as the compact file icon in Finder's list view.

<img src="Docs/Images/finder-list.png" width="720" alt="Custom BundlePack icon displayed in Finder list view">

### Custom Package Icons

Each package can have its own icon:

- select **Choose Icon…** or drop an image onto the icon preview;
- select the remove button to return to the built-in default icon;
- BundlePack normalizes the image to a transparent 1024 × 1024 PNG and stores it as `icon.png`;
- Finder uses the embedded icon for thumbnails, and BundlePack also applies it as the file's custom icon for compact list views.

The macOS app supports PNG, JPEG, TIFF, HEIC, and SVG images. The Windows app supports PNG, JPEG, BMP, and TIFF images. Both applications preserve the source aspect ratio, center the image on a transparent canvas, and store it as a 1024 × 1024 `icon.png`.

The package icon is always public, including in encrypted packages, because Finder must read it without a password. Do not use an image that contains private information.

Finder custom icons are also stored in macOS extended attributes. Some ZIP tools, cloud services, or non-Mac filesystems remove those attributes during transfer. The embedded `icon.png` remains part of the package, and opening the package in BundlePack applies the custom Finder icon again.

### Refreshing Finder Caches

If Finder continues to display an older preview or icon after replacing the app, close Quick Look and run:

```sh
qlmanage -r cache
```

## Windows Explorer Thumbnails

The Windows source includes an optional stream-based Explorer thumbnail provider
for x64 and ARM64. It reads only the public `icon.png` representation and works
for encrypted and unencrypted packages without a password. It does not expose
the manifest, file names, or contents.

The Windows Setup executable registers it automatically. Source builds can use
the development registration instructions in
[Windows/README.md](Windows/README.md). The registration remains optional; the
Create and Open workflows work without the Shell extension.

## Package Formats

The complete binary and ZIP layout is documented in [Docs/FORMAT.md](Docs/FORMAT.md).

The file format is platform-neutral. Swift/CryptoKit and C#/.NET implement the same encryption and archive rules independently. Checked-in macOS fixtures and Windows-generated CI fixtures verify archive compatibility and Unicode password normalization in both directions.

### Encrypted

An encrypted package exposes only its public package icon and container parameters. The complete inner ZIP archive is encrypted, including:

- file and folder names;
- file contents;
- package metadata such as name, author, and description;
- the ZIP central directory and archive structure.

```text
Sample.bundlepack
├── fixed header
├── public icon.png
└── AES-256-GCM encrypted chunks
    └── inner.zip
        ├── icon.png
        ├── manifest.json
        └── payload/
```

Keys are derived with PBKDF2-HMAC-SHA256 using 600,000 iterations. The archive is authenticated in 4 MiB chunks, with a unique nonce and authentication tag for every chunk. Decryption fails if the password is wrong or the package has been modified.

The public icon is intentionally not encrypted because Finder needs it for thumbnails. Use the default icon if a custom image could reveal sensitive information.

### Unencrypted

An unencrypted `.bundlepack` file is a standard ZIP archive. Rename it to `.zip` to open it with a regular archive utility. File names, metadata, and contents are available to ZIP-capable tools and file scanners; BundlePack still leaves Quick Look on the standard generic document preview.

## Security Boundaries

BundlePack rejects absolute archive paths, `..` traversal, symbolic links, encrypted ZIP entries, unsupported compression methods, duplicate output paths, and packages that exceed extraction limits. Passwords are not saved, and there is no password recovery mechanism.

Share the password through a different channel from the package. BundlePack is not a substitute for secure transport, endpoint security, or a reviewed backup strategy.

Current archive limits:

- fewer than 10,000 entries;
- no individual file of 4 GB or more;
- no more than 20 GB after expansion;
- bounded UTF-8 display metadata and package-icon inputs;
- no ZIP64 inner archives.

## Icon Generation

`Scripts/render-app-icon.swift` is the source of truth for `AppIcon.icns`, the Windows `AppIcon.ico`, and `DefaultPackageIcon.png`.

- `AppIcon.icns` is the BundlePack application and document-type icon.
- `Windows/BundlePack.Windows/Assets/AppIcon.ico` is embedded in the Windows executable.
- `DefaultPackageIcon.png` is embedded when the user does not choose a package-specific image.
- A custom package icon changes only that `.bundlepack` file; it does not replace the BundlePack application icon.

The app icon and default package icon intentionally use the same design. Package-specific icons override the default through the embedded public PNG and the Finder custom-icon metadata described above.

Regenerate the checked-in icon outputs with:

```sh
./Scripts/generate-icons.sh
```

Intermediate `.iconset` files are created in the temporary directory and are not stored in the repository.

## Project Layout

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for component ownership,
compatibility gates, and the format-change checklist.

```text
BundlePack/App/                 SwiftUI app and package workflows
BundlePack/App/Views/           macOS screens and shared view components
BundlePack/Shared/              container, manifest, and ZIP validation
BundlePack/ThumbnailExtension/  Finder thumbnail provider
Docs/                           screenshots and file-format documentation
global.json                     repository-wide .NET 10 SDK selection
Scripts/                        build, test, and icon generation scripts
Tests/                          end-to-end and drag-and-drop smoke tests
Tests/Compatibility/            checked-in macOS interoperability fixtures
Windows/BundlePack.Core/        cross-platform C# format implementation
Windows/BundlePack.Windows/     native WinUI 3 application
Windows/BundlePack.Thumbnail/   Explorer thumbnail COM server
Windows/BundlePack.Thumbnail.Tests/ Windows thumbnail rendering tests
Windows/BundlePack.Core.Tests/  Windows creation and compatibility tests
Windows/Installer/              x64 and ARM64 Inno Setup definitions
Windows/Scripts/                optional per-user Windows shell integration
Windows/Tests/                  Windows-only shell integration tests
```

## Product Identifiers

- document UTI: `com.tuki0918.bundlepack`
- app: `com.tuki0918.BundlePack`
- thumbnail extension: `com.tuki0918.BundlePack.Thumbnail`

The unpackaged Windows app does not currently register a package identity.

## Project Status

BundlePack is an experimental project. Windows binaries should be built and
tested on Windows before distribution. Review the format and both cryptographic
implementations before relying on BundlePack for high-value or irreplaceable
data.

- See [SECURITY.md](SECURITY.md) to report vulnerabilities privately.
- See [CONTRIBUTING.md](CONTRIBUTING.md) for development and pull-request guidance.
- See [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

BundlePack is available under the [MIT License](LICENSE).
