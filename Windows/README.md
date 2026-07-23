# BundlePack for Windows

This directory contains the native Windows implementation of BundlePack.

Both native applications implement the shared
[file-format specification](../Docs/FORMAT.md) independently and do not share
UI code. Return to the [project overview](../README.md).

## Projects

- `BundlePack.Core` implements the shared `.bundlepack` format, encryption, ZIP validation, creation, and extraction. It does not depend on WinUI and can be tested on any platform with .NET 10.
- `BundlePack.Windows` is the WinUI 3 desktop application for Windows 10 version 1809 or later.
- `BundlePack.Thumbnail` is the stream-based Explorer thumbnail COM server.
- `BundlePack.Thumbnail.Tests` renders encrypted and unencrypted fixtures into 32-bit DIB sections on Windows.
- `BundlePack.Core.Tests` creates Windows packages and opens the checked-in macOS compatibility fixtures.
- `Installer` contains the shared and architecture-specific Inno Setup definitions.
- `Scripts/Build.ps1` and `Scripts/Test.ps1` provide the standard one-command build and verification entry points.
- `Directory.Build.props` centralizes shared compiler, version, repository, and warning settings.

## Requirements

- Windows 10 version 1809 or later;
- Visual Studio 2026 with the Windows application development workload;
- .NET 10 SDK;
- Windows App SDK 2.2, restored automatically through NuGet.

The repository-level `global.json` selects .NET 10 and allows roll-forward to
the newest installed .NET 10 feature band.

## Build and Run

Open `BundlePack.Windows.sln` in Visual Studio, select `BundlePack.Windows`, choose `x64` or `ARM64`, and run it.

From a Developer PowerShell prompt:

```powershell
.\Windows\Scripts\Test.ps1
.\Windows\Scripts\Build.ps1
```

`Test.ps1` restores dependencies in locked mode, builds the x64 application,
runs the core compatibility and thumbnail tests, and verifies temporary
current-user file-association registration and cleanup. Pass
`-SkipFileAssociation` when registry integration is intentionally out of scope.
`Build.ps1` builds x64 and ARM64 by default; use `-Platforms x64` or
`-Platforms ARM64` to build one architecture.

NuGet dependency graphs are recorded in each project's `packages.lock.json`.
After an intentional package change, regenerate and review both platform
graphs before committing them:

```powershell
dotnet restore .\Windows\BundlePack.Windows.sln -p:Platform=x64 --force-evaluate
dotnet restore .\Windows\BundlePack.Windows.sln -p:Platform=ARM64 --force-evaluate
```

The WinUI project is currently unpackaged. It creates new archives and supports
choosing or dropping `.bundlepack` files to open them. The Explorer thumbnail
provider is built separately and is opt-in for source builds.

This output is intended for development and CI verification. Before publishing
a Windows binary, run the complete workflow and device checks, provide the
required runtimes, and sign the application, thumbnail provider, and installer.

Successful pushes to `main` publish separate x64 and ARM64 CI artifacts for
seven days. Each artifact keeps the full unpackaged app output together and
includes the Explorer thumbnail provider plus the current-user registration and
removal scripts. Pull requests retain only one-day internal artifacts needed by
downstream installer and compatibility jobs.

Run `BundlePack.Windows.exe` in place after extracting an application artifact.
Install the matching .NET 10 and Windows App Runtime prerequisites if necessary.
A matching `v<version>` tag attaches versioned application ZIPs, installers, and
SHA-256 checksums to an automatically created GitHub prerelease. Those Release
Assets remain available until the release is deleted and receive GitHub
build-provenance attestations. All automated Windows applications and installers
are framework-dependent, unsigned testing builds.

## CI Test Installers

The `BundlePack-Windows-Installers-<commit>` artifact contains:

- `BundlePack-Setup-x64.exe` for Intel and AMD Windows;
- `BundlePack-Setup-arm64.exe` for ARM64 Windows;
- a SHA-256 checksum beside each installer.

Setup installs BundlePack for the current user under
`%LocalAppData%\Programs\BundlePack`, creates a Start menu shortcut, adds the
application to **Open with**, and registers the architecture-matched Explorer
thumbnail provider. No PowerShell command or administrator prompt is required.
Windows still controls the user's default app choice and may ask which app should
open `.bundlepack` the first time.

Each installer build stores its thumbnail provider in a content-addressed
subdirectory. This allows an update to register the new provider without
overwriting the previous DLL while Explorer still has it loaded in COM
Surrogate. Reinstalling the exact same build reuses the existing provider files.

Uninstall BundlePack from Windows **Settings > Apps > Installed apps**. The
uninstaller removes the installed files and only the BundlePack-owned ProgID,
capabilities, COM class, thumbnail handler, and shared registry values.

The application and managed thumbnail COM server remain framework-dependent.
Install the matching .NET 10 and Windows App Runtime prerequisites if Windows
reports that a runtime is missing. The CI installers are unsigned test builds;
SmartScreen may warn about them, and they are not release binaries.

The installer definitions are in `Windows/Installer`. Build both installers on
Windows with Inno Setup 6.3 or later after preparing the raw CI application
directories:

```powershell
.\Windows\Scripts\Build.ps1
.\Windows\Scripts\Package-CIArtifacts.ps1
.\Windows\Scripts\Build-Installers.ps1
.\Windows\Scripts\Package-ReleaseAssets.ps1
```

The final command creates the same versioned ZIP, installer copies, and SHA-256
files that the tag workflow publishes.

CI compiles both architectures on `windows-2022`, installs and uninstalls the
x64 Setup executable, and verifies its files and registry cleanup. ARM64 Setup
execution is covered by the manual device checklist below.

## Explorer Thumbnails

The optional stream-based Explorer thumbnail provider is available for x64 and
ARM64. It reads only the public `icon.png` representation and works for
encrypted and unencrypted packages without a password. It does not expose the
manifest, file names, or contents.

The Setup executable registers the provider automatically. Source builds can
use the development registration steps below. The Create and Open workflows do
not require the Shell extension.

## Custom Package Icons

The Windows app supports PNG, JPEG, BMP, TIFF, and animated GIF source images.
It preserves the source aspect ratio, centers the image on a transparent
canvas, and stores it as a 1024 × 1024 `icon.png`.

For a GIF, the first frame becomes the public `icon.png`; the animation plays
only on BundlePack's validated Open screen and, for encrypted packages, only
after unlock. Explorer remains static, and the Windows animation accessibility
setting is respected. Animated WebP is not currently supported.

The package icon is always public, including in encrypted packages, because
Explorer must read it without a password. Do not use an image that contains
private information.

## Optional File Association for Development Builds

After building the app, add it to Windows **Open with** for the current user:

```powershell
.\Windows\Scripts\Register-FileAssociation.ps1 `
  -ExecutablePath "C:\path\to\BundlePack.Windows.exe" `
  -ThumbnailProviderPath "C:\path\to\BundlePack.Thumbnail.comhost.dll"
```

`ThumbnailProviderPath` is optional. When supplied, keep the entire thumbnail
build-output directory together because the COM host loads its managed assembly,
runtime configuration, and dependencies from that directory.

The script does not require administrator privileges and does not force a new default application. Windows may ask you to choose BundlePack the first time you open a `.bundlepack` file. Remove both the file and thumbnail registration with:

```powershell
.\Windows\Scripts\Unregister-FileAssociation.ps1
```

CI renders all macOS- and Windows-generated fixtures through the x64 provider,
builds the ARM64 provider, performs registration in the runner's current-user
registry, verifies the ProgID, icon, open command, supported type, capabilities,
COM server, and Shell handler, then removes the registration again.

## ARM64 Device Verification

CI compiles the WinUI app and Explorer thumbnail provider for ARM64, but the
hosted runner does not execute ARM64 binaries. Before an ARM64 binary release,
perform this checklist on an ARM64 Windows device:

1. Build `BundlePack.Windows` and `BundlePack.Thumbnail` with `-p:Platform=ARM64`.
2. Run the app and create encrypted and unencrypted packages containing a file,
   a zero-byte file, and an empty folder.
3. Open the packages, cancel one long operation, unlock the encrypted package,
   and extract both packages.
4. Register the development file association and thumbnail provider with
   `Register-FileAssociation.ps1`.
5. Confirm double-click opening, the custom icon in Explorer icon and list
   views, and thumbnails for encrypted and unencrypted packages.
6. Run `Unregister-FileAssociation.ps1` and confirm the ProgID and thumbnail
   handler are removed.

Record the Windows version, device architecture, and result in the release
notes. This is a manual release gate until an ARM64 Windows runner executes the
same checks automatically.
