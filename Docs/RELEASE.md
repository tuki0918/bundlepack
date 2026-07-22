# Release Checklist

BundlePack `0.1.x` is experimental. Source publication and end-user binary
distribution have different requirements.

## Current recommendation

Publish the repository and, if desired, create a source-only GitHub release.
Do not attach locally built macOS or Windows application binaries yet.

Successful CI runs provide short-lived macOS universal, Windows x64, Windows
ARM64, and Windows installer artifacts for testing. They are ad-hoc signed or
unsigned development builds, not approved release assets.

## Source-only release

1. Confirm the version and release notes in `CHANGELOG.md`.
2. Run `./macOS/Scripts/test.sh` and `./macOS/Scripts/build.sh` on macOS.
3. Commit and push the intended files without signing credentials or generated build output.
4. Wait for every job in `.github/workflows/ci.yml` to pass.
5. Create the Git tag and GitHub release without binary attachments. GitHub provides source-code ZIP and tar archives automatically.

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
