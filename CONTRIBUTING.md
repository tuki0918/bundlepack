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
Windows share the same release version, platform minimums, and macOS build
number. Swift source registrations are checked against the filesystem,
command-line build, and Xcode project so newly added files cannot be silently
omitted. Both native test suites verify their v1 constants against
`Fixtures/FormatV1.json`.

The build output is written to `.build/BundlePack.app` and is ad-hoc signed for local testing.

Run the Windows core checks from a Developer PowerShell prompt:

```powershell
.\Windows\Scripts\Test.ps1
.\Windows\Scripts\Build.ps1
```

Windows restores use committed `packages.lock.json` files. Regenerate both x64
and ARM64 lock graphs with `--force-evaluate` after an intentional package
change, then review and commit the resulting lock-file changes.

When changing the Windows installer, build both application architectures and
then run the packaging and installer checks from a Developer PowerShell prompt:

```powershell
.\Windows\Scripts\Build.ps1
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
