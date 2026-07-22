# Repository Scripts

These scripts perform repository-wide maintenance from macOS:

- `clean.sh` removes generated macOS and Windows build output.
- `generate-icons.sh` regenerates the macOS and Windows application icons and both copies of the default package icon.
- `verify-project-metadata.sh` checks cross-platform versions, platform minimums, identifiers, default icons, and Swift source registration.
- `IconGeneration` contains the Swift helpers used by `generate-icons.sh`.

Run scripts from the repository root. Platform-specific build, test, packaging,
and release scripts remain under `macOS/Scripts` and `Windows/Scripts`.
