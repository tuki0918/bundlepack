# BundlePack File Format

BundlePack `0.1.x` writes one of two formats using the `.bundlepack` extension.

## Common metadata

The inner ZIP contains:

```text
icon.png
manifest.json
payload/
```

`manifest.json` uses format identifier `com.tuki0918.bundlepack` and format version `1`. Readers reject other identifiers and versions.

The icon is normalized to a transparent 1024 × 1024 PNG. It is public in both package formats.

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

- absolute paths, traversal components, backslashes, colons, NUL bytes, and symbolic links;
- duplicate or filesystem-normalized output paths;
- encrypted ZIP entries and unsupported compression methods;
- ZIP64 packages, 10,000 or more entries, and expanded data above 20 GiB;
- malformed, truncated, oversized, unauthenticated, or unsupported encrypted containers.

The format is experimental. Future incompatible formats must use a new container or manifest version.
