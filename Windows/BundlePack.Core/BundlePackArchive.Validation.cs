using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;

namespace BundlePack.Core;

public static partial class BundlePackArchive
{
    private static async Task<IReadOnlyList<ZipEntryRecord>> ParseAndValidateAsync(
        string path,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                128 * 1_024,
                FileOptions.Asynchronous | FileOptions.RandomAccess);
            if (stream.Length < 22)
            {
                throw new BundlePackException(BundlePackError.NotZip, "The file is not a BundlePack or ZIP archive.");
            }

            var tailLength = checked((int)Math.Min(stream.Length, 65_557));
            var tail = new byte[tailLength];
            stream.Position = stream.Length - tailLength;
            await FileHelpers.ReadExactlyAsync(stream, tail, cancellationToken).ConfigureAwait(false);

            var endOffset = -1;
            for (var offset = tail.Length - 22; offset >= 0; offset--)
            {
                if (BinaryPrimitives.ReadUInt32LittleEndian(tail.AsSpan(offset, 4)) == EndOfCentralDirectorySignature)
                {
                    endOffset = offset;
                    break;
                }
            }

            if (endOffset < 0)
            {
                throw new BundlePackException(BundlePackError.NotZip, "The file is not a BundlePack or ZIP archive.");
            }

            var diskNumber = BinaryPrimitives.ReadUInt16LittleEndian(tail.AsSpan(endOffset + 4, 2));
            var centralDirectoryDisk = BinaryPrimitives.ReadUInt16LittleEndian(tail.AsSpan(endOffset + 6, 2));
            var entriesOnDisk = BinaryPrimitives.ReadUInt16LittleEndian(tail.AsSpan(endOffset + 8, 2));
            var entryCount = BinaryPrimitives.ReadUInt16LittleEndian(tail.AsSpan(endOffset + 10, 2));
            var centralSize = BinaryPrimitives.ReadUInt32LittleEndian(tail.AsSpan(endOffset + 12, 4));
            var centralOffset = BinaryPrimitives.ReadUInt32LittleEndian(tail.AsSpan(endOffset + 16, 4));
            var archiveCommentLength = BinaryPrimitives.ReadUInt16LittleEndian(tail.AsSpan(endOffset + 20, 2));
            var absoluteEndOffset = checked((ulong)(stream.Length - tailLength + endOffset));
            if (diskNumber != 0
                || centralDirectoryDisk != 0
                || entriesOnDisk != entryCount
                || endOffset + 22 + archiveCommentLength != tail.Length
                || (ulong)centralOffset + centralSize != absoluteEndOffset)
            {
                throw new BundlePackException(BundlePackError.NotZip, "The ZIP central directory is invalid.");
            }

            if (entryCount == ushort.MaxValue || centralSize == uint.MaxValue || centralOffset == uint.MaxValue)
            {
                throw new BundlePackException(BundlePackError.Zip64Unsupported, "ZIP64 packages are not supported.");
            }

            if (entryCount >= BundlePackConstants.MaximumEntries + 1)
            {
                throw new BundlePackException(BundlePackError.ArchiveTooLarge, "The expanded size or file count exceeds the safety limit.");
            }

            if ((ulong)centralOffset + centralSize > (ulong)stream.Length)
            {
                throw new BundlePackException(BundlePackError.NotZip, "The ZIP central directory is invalid.");
            }

            stream.Position = centralOffset;
            var records = new List<ZipEntryRecord>(entryCount);
            ulong centralBytesRead = 0;
            for (var index = 0; index < entryCount; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var header = new byte[46];
                await FileHelpers.ReadExactlyAsync(stream, header, cancellationToken).ConfigureAwait(false);
                centralBytesRead += 46;
                if (BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(0, 4)) != CentralFileHeaderSignature)
                {
                    throw new BundlePackException(BundlePackError.NotZip, "The ZIP central directory is invalid.");
                }

                var flags = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(8, 2));
                var compressionMethod = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(10, 2));
                var crc32 = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(16, 4));
                var compressedSize = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(20, 4));
                var uncompressedSize = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(24, 4));
                var nameLength = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(28, 2));
                var extraLength = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(30, 2));
                var commentLength = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(32, 2));
                var externalAttributes = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(38, 4));
                var localHeaderOffset = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(42, 4));
                if (compressedSize == uint.MaxValue || uncompressedSize == uint.MaxValue || localHeaderOffset == uint.MaxValue)
                {
                    throw new BundlePackException(BundlePackError.Zip64Unsupported, "ZIP64 packages are not supported.");
                }

                var variableLength = checked(nameLength + extraLength + commentLength);
                var variableData = new byte[variableLength];
                await FileHelpers.ReadExactlyAsync(stream, variableData, cancellationToken).ConfigureAwait(false);
                centralBytesRead += checked((uint)variableLength);

                string entryPath;
                try
                {
                    entryPath = StrictUtf8.GetString(variableData, 0, nameLength);
                }
                catch (DecoderFallbackException exception)
                {
                    throw new BundlePackException(BundlePackError.InvalidEntry, "A ZIP entry name is not valid UTF-8.", exception);
                }

                records.Add(new ZipEntryRecord(
                    entryPath,
                    flags,
                    compressionMethod,
                    crc32,
                    compressedSize,
                    uncompressedSize,
                    localHeaderOffset,
                    externalAttributes));
            }

            if (centralBytesRead != centralSize)
            {
                throw new BundlePackException(BundlePackError.NotZip, "The ZIP central directory is invalid.");
            }

            ValidateRecords(records, checked((ulong)stream.Length));
            return records;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (BundlePackException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new BundlePackException(BundlePackError.UnreadableArchive, "The package could not be read.", exception);
        }
    }

    private static void ValidateRecords(IReadOnlyList<ZipEntryRecord> records, ulong archiveSize)
    {
        ulong expandedSize = 0;
        var outputPaths = new HashSet<string>(FileHelpers.OutputPathComparer);
        var filePaths = new HashSet<string>(FileHelpers.OutputPathComparer);

        foreach (var record in records)
        {
            if (!IsAllowedBundlePackPath(record.Path))
            {
                throw new BundlePackException(BundlePackError.InvalidEntry, $"A ZIP entry is not part of the BundlePack layout: {record.Path}");
            }

            if (!IsSafeArchivePath(record.Path))
            {
                throw new BundlePackException(BundlePackError.UnsafeEntry, $"An unsafe path was detected: {record.Path}");
            }

            var canonicalPath = CanonicalOutputPath(record.Path);
            if (!outputPaths.Add(canonicalPath))
            {
                throw new BundlePackException(
                    BundlePackError.DuplicateEntry,
                    $"Multiple ZIP entries resolve to the same output path: {record.Path}");
            }

            if (!record.Path.EndsWith('/'))
            {
                filePaths.Add(canonicalPath);
            }

            if ((record.Flags & 0x0001) != 0)
            {
                throw new BundlePackException(BundlePackError.EncryptedZipEntry, $"Encrypted ZIP entries are not supported: {record.Path}");
            }

            if (record.CompressionMethod is not 0 and not 8)
            {
                throw new BundlePackException(
                    BundlePackError.UnsupportedCompression,
                    $"The compression method is not supported: {record.Path}");
            }

            var unixMode = (ushort)((record.ExternalAttributes >> 16) & 0xffff);
            if ((unixMode & 0xf000) == 0xa000)
            {
                throw new BundlePackException(BundlePackError.UnsafeEntry, $"A symbolic link was detected: {record.Path}");
            }

            try
            {
                expandedSize = checked(expandedSize + record.UncompressedSize);
            }
            catch (OverflowException)
            {
                throw new BundlePackException(BundlePackError.ArchiveTooLarge, "The expanded size exceeds the safety limit.");
            }
        }

        foreach (var path in outputPaths)
        {
            var components = path.Split('/');
            if (components.Length < 2)
            {
                continue;
            }

            var parent = string.Empty;
            foreach (var component in components[..^1])
            {
                parent = parent.Length == 0 ? component : $"{parent}/{component}";
                if (filePaths.Contains(parent))
                {
                    throw new BundlePackException(
                        BundlePackError.DuplicateEntry,
                        $"A file and directory resolve to the same output path: {path}");
                }
            }
        }

        if (expandedSize > (ulong)BundlePackConstants.MaximumExpandedSize
            || (archiveSize > 0
                && expandedSize > 1UL * 1_024 * 1_024 * 1_024
                && expandedSize / archiveSize > 1_000))
        {
            throw new BundlePackException(BundlePackError.ArchiveTooLarge, "The expanded size exceeds the safety limit.");
        }
    }

    private static bool IsSafeArchivePath(string path)
    {
        if (string.IsNullOrEmpty(path)
            || path.StartsWith('/')
            || path.Contains('\\')
            || path.Contains(':')
            || path.Contains('\0'))
        {
            return false;
        }

        var withoutDirectoryMarker = path.EndsWith('/') ? path[..^1] : path;
        if (withoutDirectoryMarker.Length == 0)
        {
            return false;
        }

        var components = withoutDirectoryMarker.Split('/');
        return components.All(component => component.Length > 0
                && component is not "." and not ".."
                && FileHelpers.IsPortableFileName(component))
            && components[0] != "~";
    }

    private static bool IsAllowedBundlePackPath(string path) =>
        path is "icon.png" or "manifest.json" or BundlePackConstants.AnimationPath or "payload/"
        || path.StartsWith("payload/", StringComparison.Ordinal);

    private static string CanonicalOutputPath(string path)
    {
        var withoutDirectoryMarker = path.EndsWith('/') ? path[..^1] : path;
        return FileHelpers.NormalizeOutputPath(withoutDirectoryMarker);
    }

    private static async Task<byte[]> ReadMetadataAsync(
        ZipArchive archive,
        ZipEntryRecord record,
        CancellationToken cancellationToken)
    {
        var entry = archive.Entries.SingleOrDefault(candidate => candidate.FullName == record.Path)
            ?? throw new BundlePackException(BundlePackError.InvalidEntry, $"A ZIP entry is missing: {record.Path}");
        await using var output = new MemoryStream(checked((int)record.UncompressedSize));
        await CopyAndValidateEntryAsync(entry, record, output, cancellationToken).ConfigureAwait(false);
        return output.ToArray();
    }

    private static async Task CopyAndValidateEntryAsync(
        ZipArchiveEntry entry,
        ZipEntryRecord record,
        Stream output,
        CancellationToken cancellationToken,
        Action<ulong>? didCopy = null)
    {
        if ((ulong)entry.Length != record.UncompressedSize || (ulong)entry.CompressedLength != record.CompressedSize)
        {
            throw new BundlePackException(BundlePackError.InvalidEntry, $"A ZIP entry is inconsistent: {record.Path}");
        }

        await using var input = entry.Open();
        var crc32 = new Crc32Calculator();
        var buffer = new byte[128 * 1_024];
        var remaining = record.UncompressedSize;
        while (remaining > 0)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var requested = checked((int)Math.Min((ulong)buffer.Length, remaining));
            var count = await input.ReadAsync(buffer.AsMemory(0, requested), cancellationToken).ConfigureAwait(false);
            if (count == 0)
            {
                throw new BundlePackException(BundlePackError.InvalidEntry, $"A ZIP entry is truncated: {record.Path}");
            }

            crc32.Append(buffer.AsSpan(0, count));
            await output.WriteAsync(buffer.AsMemory(0, count), cancellationToken).ConfigureAwait(false);
            remaining -= checked((uint)count);
            didCopy?.Invoke(checked((ulong)count));
        }

        if (await input.ReadAsync(buffer.AsMemory(0, 1), cancellationToken).ConfigureAwait(false) != 0)
        {
            throw new BundlePackException(
                BundlePackError.ArchiveTooLarge,
                $"A ZIP entry expands beyond its declared size: {record.Path}");
        }

        if (crc32.Value != record.Crc32)
        {
            throw new BundlePackException(BundlePackError.InvalidEntry, $"A ZIP entry failed its CRC check: {record.Path}");
        }
    }

    private static void ValidateManifestFiles(
        BundlePackManifest manifest,
        IReadOnlyList<BundlePackFile> payloadFiles)
    {
        if (manifest.Files is null)
        {
            throw new BundlePackException(BundlePackError.InvalidManifest, "manifest.json has no file list.");
        }

        var manifestFiles = manifest.Files
            .OrderBy(file => file.Path, StringComparer.Ordinal)
            .ThenBy(file => file.Size)
            .ToArray();
        var actualFiles = payloadFiles
            .OrderBy(file => file.Path, StringComparer.Ordinal)
            .ThenBy(file => file.Size)
            .ToArray();
        if (!manifestFiles.SequenceEqual(actualFiles))
        {
            throw new BundlePackException(
                BundlePackError.InvalidManifest,
                "The manifest file list does not match the package payload.");
        }
    }

    private sealed record ZipEntryRecord(
        string Path,
        ushort Flags,
        ushort CompressionMethod,
        uint Crc32,
        ulong CompressedSize,
        ulong UncompressedSize,
        ulong LocalHeaderOffset,
        uint ExternalAttributes);
}
