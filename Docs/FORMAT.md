# BundlePack File Format

BundlePack `0.1.x` writes one of two formats using the `.bundlepack` extension.

## Common metadata

The inner ZIP contains:

```text
icon.png
manifest.json
payload/
```

No other root entries are permitted. The ZIP must be a complete single-disk
archive; an optional ZIP comment is allowed, but bytes appended beyond the
declared comment are rejected.

`manifest.json` uses format identifier `com.tuki0918.bundlepack` and format version `1`. Readers reject other identifiers and versions.

The manifest is UTF-8 JSON with these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `format` | string | `com.tuki0918.bundlepack` |
| `formatVersion` | integer | `1` |
| `title` | string | Display and extraction-folder name |
| `packageVersion` | string | User-provided package version |
| `author` | string | Optional author text |
| `summary` | string | Optional description text |
| `createdAt` | string | ISO-8601 creation timestamp |
| `files` | array | Objects containing a payload-relative `/`-separated `path` and byte `size` |

Display fields must not contain Unicode control characters. Their maximum
UTF-8 encoded lengths are 256 bytes for `title`, 64 bytes for
`packageVersion`, 256 bytes for `author`, and 4,096 bytes for `summary`.
`title` must contain at least one non-whitespace character. The other display
fields may be empty.

The icon is normalized to a transparent 1024 × 1024 PNG. It is public in both package formats.

## Platform interoperability

The format is platform-neutral. The native macOS implementation uses Swift, CryptoKit, and CommonCrypto. The native Windows implementation uses C# and .NET cryptography. Both implementations:

- write UTF-8 ZIP paths using `/` as the separator;
- normalize passwords to Unicode NFC before UTF-8 PBKDF2 input;
- use the exact little-endian encrypted-container layout below;
- store `icon.png` and `manifest.json` without ZIP compression;
- apply the same path, entry-count, size, ZIP64, compression, and symbolic-link restrictions.

`Fixtures/Compatibility/macOS` contains packages created by macOS and opened by
Windows tests. Windows CI creates a second fixture set that is downloaded and
opened by the macOS test job. Dedicated Unicode-password fixtures use opposite
composed/decomposed forms to verify NFC normalization in both directions. The
shared fixture passwords are test-only and documented beside the fixtures.

`Fixtures/FormatV1.json` mirrors the numeric and identifier constants in this
document so both native test suites can detect implementation drift. This
document remains the normative format specification; the JSON file is a test
expectation and must be updated only with an intentional format-contract change.

## Unencrypted packages

An unencrypted package is a standard ZIP archive. `icon.png` and `manifest.json` are stored without compression, while payload entries may use normal ZIP compression.

Unencrypted packages provide no confidentiality. File names, metadata, and contents can be inspected with standard ZIP tools.

## Encrypted packages

All integers use little-endian byte order.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII magic `BPKENC01` |
| 8 | 2 | Container version (`1`) |
| 10 | 2 | Flags (`1`) |
| 12 | 4 | PBKDF2 iteration count |
| 16 | 4 | Plaintext chunk size |
| 20 | 4 | Chunk count |
| 24 | 8 | Inner ZIP plaintext size |
| 32 | 4 | Public icon size |
| 36 | 16 | PBKDF2 salt |
| 52 | 8 | AES-GCM nonce prefix |
| 60 | 32 | SHA-256 hash of the public icon |
| 92 | variable | Public PNG icon |
| after icon | variable | Encrypted ZIP chunks and authentication tags |

The password is normalized to Unicode NFC. PBKDF2-HMAC-SHA256 derives a 32-byte key using the iteration count stored in the authenticated header. New packages currently use 600,000 iterations.

The inner ZIP is divided into 4 MiB plaintext chunks. Each chunk uses AES-256-GCM with:

- nonce: the 8-byte random prefix followed by the 32-bit chunk index;
- authenticated data: the complete fixed header followed by the 32-bit chunk index;
- output: ciphertext followed by a 16-byte authentication tag.

The public icon is authenticated by the hash in the fixed header but is intentionally not encrypted. All inner ZIP metadata, paths, and contents are encrypted.

## Validation limits

Readers reject:

- absolute paths, traversal components, backslashes, colons, NUL bytes, symbolic links, and names that are not portable between macOS and Windows;
- Windows-reserved device names, control characters, names ending in a space or period, and `<`, `>`, `"`, `|`, `?`, or `*` in path components;
- duplicate or filesystem-normalized output paths;
- manifests whose file paths or sizes do not exactly match the ZIP payload;
- display metadata containing control characters or exceeding the UTF-8 limits above;
- missing or invalid package icons, including PNG dimensions other than 1024 × 1024;
- unexpected root entries, multi-disk ZIPs, incomplete central directories, and undeclared trailing data;
- encrypted ZIP entries and unsupported compression methods;
- entries whose actual expanded size or ZIP CRC does not match the central directory;
- ZIP64 packages, 10,000 or more entries, and expanded data above 20 GiB;
- malformed, truncated, oversized, unauthenticated, or unsupported encrypted containers.

Before extraction, readers verify the actual expanded byte count and CRC of
every payload entry, rather than trusting only sizes declared in ZIP headers.
Extraction must use the same reviewed archive bytes: implementations may bind
the review to a digest or retain a private snapshot until extraction finishes.

The format is experimental. Future incompatible formats must use a new container or manifest version.
