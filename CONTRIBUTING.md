# Contributing

Thank you for contributing to BundlePack.

## Development setup

Requirements:

- for macOS changes: macOS 15 or later and Xcode with the macOS 15 SDK;
- for Windows changes: Windows 10 version 1809 or later, Visual Studio 2026, and .NET 10.
- for Windows installer changes: Inno Setup 6.3 or later.

Run the repository checks before opening a pull request:

```sh
./macOS/Scripts/test.sh
./macOS/Scripts/build.sh
```

The test script also verifies that macOS, the thumbnail extension, Xcode, and
Windows share the same release version and macOS build number. Swift source
registrations are checked against the filesystem, command-line build, and
Xcode project so newly added files cannot be silently omitted.

The build output is written to `.build/BundlePack.app` and is ad-hoc signed for local testing.

Run the Windows core checks from a Developer PowerShell prompt:

```powershell
dotnet build .\Windows\BundlePack.Core.Tests\BundlePack.Core.Tests.csproj -c Release
dotnet run --project .\Windows\BundlePack.Core.Tests -c Release -- --repo . --fixtures .\Fixtures\Compatibility\macOS --output .\.build\windows-fixtures
dotnet build .\Windows\BundlePack.Windows\BundlePack.Windows.csproj -c Release -p:Platform=x64
dotnet run --project .\Windows\BundlePack.Thumbnail.Tests -c Release -p:Platform=x64 -- --fixtures .\.build\windows-fixtures --fixtures .\Fixtures\Compatibility\macOS
```

When changing the Windows installer, build both application architectures and
then run the packaging and installer checks from a Developer PowerShell prompt:

```powershell
dotnet build .\Windows\BundlePack.Windows.sln -c Release -p:Platform=x64
dotnet build .\Windows\BundlePack.Windows.sln -c Release -p:Platform=ARM64
.\Windows\Scripts\Package-CIArtifacts.ps1
.\Windows\Scripts\Build-Installers.ps1
.\Windows\Tests\Test-Installer.ps1 `
  -InstallerPath .\.build\installers\BundlePack-Setup-x64.exe
```

ARM64 installer execution remains a device-level release check documented in
[`Windows/README.md`](Windows/README.md).

## Pull requests

- Keep changes focused and written in English.
- Add regression coverage for package-format, archive-validation, encryption, Finder, or Quick Look changes.
- Keep `Docs/FORMAT.md`, Swift, and C# implementations synchronized when changing the file format.
- Do not commit `.bundlepack` files outside `Fixtures/Compatibility/macOS`, signing certificates, provisioning profiles, passwords, or generated build output.
- Update `CHANGELOG.md` when behavior or the file format changes.

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) before changing component
boundaries or the `.bundlepack` format.

Report security issues privately using the process in [SECURITY.md](SECURITY.md).
