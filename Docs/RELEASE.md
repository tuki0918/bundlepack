# Release Checklist

BundlePack `0.1.x` is experimental. Source publication and end-user binary
distribution have different requirements.

## Current recommendation

Pull requests run lightweight native and interoperability tests. Pushes to
`main` run the same tests plus C# and Swift CodeQL; CodeQL's manual builds also
compile the x64 Windows and universal macOS applications. Neither workflow
produces downloadable application or installer artifacts. A `v<version>` tag
runs the full builds and creates a GitHub prerelease whose versioned application
and installer assets remain available until the release is deleted.

The tag must point to a commit reachable from the repository's default branch.
Before publication, the Release workflow reruns both native test suites, opens
its Windows-generated compatibility fixtures on macOS and creates provenance
attestations for every application archive and installer. CodeQL runs only for
pushes to `main`, not again for release tags.

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
   build output, then wait for CI, dependency review, and the `main` CodeQL
   checks to pass.
6. Create and push a matching tag, for example `v0.1.0`:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

7. Wait for the Release workflow to confirm that the tagged commit belongs to
   the default branch, test and build both native implementations, test the
   installers, open the generated Windows fixtures on macOS, attest the assets,
   and create the GitHub prerelease.

The workflow attaches versioned macOS and Windows application archives, x64 and
ARM64 Windows installers, and SHA-256 checksum files. Rerunning the publish job
replaces assets with the same names on the existing prerelease.

After downloading a ZIP or EXE, verify its GitHub Actions provenance with:

```sh
gh attestation verify <downloaded-asset> -R tuki0918/bundlepack
```

An attestation links an asset to its repository, workflow, commit, and build
event. It does not replace Developer ID, notarization, or Authenticode signing.

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

- complete the Windows release tests for x64 and builds for x64 and ARM64;
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
