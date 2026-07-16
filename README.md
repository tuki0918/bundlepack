# BundlePack

BundlePack is a native macOS utility for collecting files and folders into a shareable `.bundlepack` archive. Packages can be encrypted for privacy or stored as standard ZIP-compatible archives. Encryption is enabled by default.

## Highlights

- Add multiple files and folders with a file picker or drag and drop.
- Choose or drop a custom package icon displayed by Finder and the standard macOS preview.
- Encrypt file names, metadata, ZIP structure, and file contents with AES-256-GCM.
- Create unencrypted `.bundlepack` files that remain compatible with standard ZIP tools.
- Generate strong passwords with configurable length, digit count, and symbol count.
- Open `.bundlepack` files by double-clicking, choosing a file, or dragging one into the app.
- Run natively on both Apple silicon and Intel Macs.

## Screenshots

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

- macOS 15 or later
- Xcode with the macOS 15 SDK, or matching Xcode Command Line Tools

## Build from Source

Clone the repository, then run:

```sh
chmod +x Scripts/build.sh Scripts/test.sh Scripts/generate-icons.sh
./Scripts/test.sh
./Scripts/build.sh
```

The app is written to `.build/BundlePack.app`. You can also open `BundlePack.xcodeproj` and build the `BundlePack` scheme in Xcode.

The command-line build uses an ad-hoc signature for local testing. Before distributing the app, sign it with an Apple Developer ID and notarize it.

Pull requests and pushes are checked on macOS by GitHub Actions. The workflow runs the smoke tests, builds universal Intel and Apple Silicon executables, validates signatures and property lists, and uploads a short-lived CI artifact.

## Release Build

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

## Finder, Quick Look, and Custom Icons

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

A ready-to-use gift-box icon is included for testing the feature:

<img src="Docs/Images/demo-package-icon.png" width="180" alt="Gift-box demo package icon">

[Open the 1024 × 1024 transparent PNG](Docs/Images/demo-package-icon.png), then select **Choose Icon…** or drop it onto the Create screen's icon preview.

The package icon is always public, including in encrypted packages, because Finder must read it without a password. Do not use an image that contains private information.

Finder custom icons are also stored in macOS extended attributes. Some ZIP tools, cloud services, or non-Mac filesystems remove those attributes during transfer. The embedded `icon.png` remains part of the package, and opening the package in BundlePack applies the custom Finder icon again.

### Refreshing Finder Caches

If Finder continues to display an older preview or icon after replacing the app, close Quick Look and run:

```sh
qlmanage -r cache
```

## Package Formats

The complete binary and ZIP layout is documented in [Docs/FORMAT.md](Docs/FORMAT.md).

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
- no ZIP64 inner archives.

## Icon Generation

`Scripts/render-app-icon.swift` is the source of truth for both `AppIcon.icns` and `DefaultPackageIcon.png`.

- `AppIcon.icns` is the BundlePack application and document-type icon.
- `DefaultPackageIcon.png` is embedded when the user does not choose a package-specific image.
- A custom package icon changes only that `.bundlepack` file; it does not replace the BundlePack application icon.

The app icon and default package icon intentionally use the same design. Package-specific icons override the default through the embedded public PNG and the Finder custom-icon metadata described above.

Regenerate the checked-in icon outputs with:

```sh
./Scripts/generate-icons.sh
```

Intermediate `.iconset` files are created in the temporary directory and are not stored in the repository.

## Project Layout

```text
BundlePack/App/                 SwiftUI app and package workflows
BundlePack/Shared/              container, manifest, and ZIP validation
BundlePack/ThumbnailExtension/  Finder thumbnail provider
Docs/                           screenshots and file-format documentation
Scripts/                        build, test, and icon generation scripts
Tests/                          end-to-end and drag-and-drop smoke tests
```

## Product Identifiers

- document UTI: `com.tuki0918.bundlepack`
- app: `com.tuki0918.BundlePack`
- thumbnail extension: `com.tuki0918.BundlePack.Thumbnail`

## Project Status

BundlePack is an experimental project. Review the format and cryptographic implementation before relying on it for high-value or irreplaceable data.

- See [SECURITY.md](SECURITY.md) to report vulnerabilities privately.
- See [CONTRIBUTING.md](CONTRIBUTING.md) for development and pull-request guidance.
- See [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

BundlePack is available under the [MIT License](LICENSE).
