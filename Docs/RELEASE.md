# Release Checklist

BundlePack `0.1.x` is experimental. Source publication and end-user binary
distribution have different requirements.

## Current recommendation

Successful pushes to `main` provide macOS universal, Windows x64, Windows ARM64,
and Windows installer artifacts for seven days. A `v<version>` tag creates a
GitHub prerelease whose versioned application and installer assets remain
available until the release is deleted.

The automated macOS application is ad-hoc signed and not notarized. Automated
Windows applications and installers are unsigned. Keep these releases marked as
prereleases and describe their assets as testing builds, not trusted end-user
binaries.

## Automated test prerelease

1. Confirm the version and release notes in `CHANGELOG.md`.
2. Keep `CFBundleShortVersionString`, Xcode `MARKETING_VERSION`, and Windows
   `VersionPrefix` synchronized.
3. Run `./macOS/Scripts/test.sh` and `./macOS/Scripts/build.sh` on macOS.
4. Run `.\Windows\Scripts\Test.ps1` and `.\Windows\Scripts\Build.ps1` on Windows.
5. Commit and push the intended files without signing credentials or generated
   build output, then wait for CI, dependency review, and CodeQL to pass.
6. Create and push a matching tag, for example `v0.1.0`:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

7. Wait for the Release workflow to test both native implementations, build all
   assets, verify the tag version, and create the GitHub prerelease.

The workflow attaches versioned macOS and Windows application archives, x64 and
ARM64 Windows installers, and SHA-256 checksum files. Rerunning the publish job
replaces assets with the same names on the existing prerelease.

## macOS binary release

Public distribution requires all of the following:

- active Apple Developer Program membership;
- a valid **Developer ID Application** identity in the signing keychain;
- successful hardened-runtime signing, notarization, stapling, and Gatekeeper assessment;
- a clean result from `./macOS/Scripts/release.sh`.

An **Apple Development** certificate, ad-hoc signature, dummy identity, or a
renamed local `.app` is not sufficient for a trusted public release. The
release script creates `.build/release/BundlePack-<version>.zip` only after the
required checks succeed.

## Windows binary release

The WinUI 3 application remains unpackaged internally and is wrapped by separate
Inno Setup x64 and ARM64 installers. Before distributing it to end users:

- complete the Windows CI tests for x64 and builds for x64 and ARM64;
- complete the ARM64 device checklist in `Windows/README.md`;
- test create, open, encrypted interoperability, extraction, file association,
  and Explorer thumbnails on supported Windows versions;
- verify the Inno Setup install, upgrade, uninstall, file association, and
  thumbnail registration behavior on x64 and ARM64;
- bundle the required .NET and Windows App Runtime prerequisites or document and
  validate their installation path;
- Authenticode-sign the distributed executable, COM thumbnail provider, and
  installer or package with a trusted certificate;
- test install, upgrade, uninstall, and registry cleanup from a standard user account.

## Security communication

- State that custom icons are public even when package contents are encrypted.
- State that unencrypted packages provide no confidentiality.
- Recommend sharing passwords through a separate channel.
- Keep the experimental and not-independently-audited notice from `SECURITY.md`.
- Do not claim that a passing test suite guarantees complete security.
