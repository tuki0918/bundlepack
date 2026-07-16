# Security Policy

## Supported versions

BundlePack is currently a `0.1.x` experimental release. Security fixes are made on the latest revision of the `main` branch.

## Reporting a vulnerability

Please use GitHub's private **Report a vulnerability** flow for this repository. Do not include passwords, private package contents, or exploit details in a public issue.

If private reporting is unavailable, open a public issue containing only a request for a private contact channel. Do not publish reproduction files or sensitive technical details there.

## Security boundaries

- A custom package icon is public and is not encrypted.
- Passwords are not persisted, and copied generated passwords are cleared from the clipboard after 60 seconds when unchanged.
- Encrypted packages use PBKDF2-HMAC-SHA256 and chunked AES-256-GCM authentication.
- Unencrypted packages are ZIP-compatible and provide no confidentiality.
- BundlePack is not independently audited. Do not rely on experimental releases as the only copy of irreplaceable data.

See [Docs/FORMAT.md](Docs/FORMAT.md) for the file-format security boundary.
