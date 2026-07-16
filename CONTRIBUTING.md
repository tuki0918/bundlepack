# Contributing

Thank you for contributing to BundlePack.

## Development setup

Requirements:

- macOS 15 or later;
- Xcode with the macOS 15 SDK, or matching Command Line Tools.

Run the repository checks before opening a pull request:

```sh
./Scripts/test.sh
./Scripts/build.sh
```

The build output is written to `.build/BundlePack.app` and is ad-hoc signed for local testing.

## Pull requests

- Keep changes focused and written in English.
- Add regression coverage for package-format, archive-validation, encryption, Finder, or Quick Look changes.
- Do not commit `.bundlepack` files, signing certificates, provisioning profiles, passwords, or generated build output.
- Update `CHANGELOG.md` when behavior or the file format changes.

Report security issues privately using the process in [SECURITY.md](SECURITY.md).
