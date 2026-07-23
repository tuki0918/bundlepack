using System.IO.Compression;
using System.Text;
using System.Text.Json;

namespace BundlePack.Core;

public static partial class BundlePackArchive
{
    private const uint EndOfCentralDirectorySignature = 0x0605_4b50;
    private const uint CentralFileHeaderSignature = 0x0201_4b50;
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);

    public static async Task<BundlePackArchiveInfo> InspectAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        var records = await ParseAndValidateAsync(path, cancellationToken).ConfigureAwait(false);
        var manifestRecord = records.FirstOrDefault(record => record.Path == "manifest.json")
            ?? throw new BundlePackException(BundlePackError.MissingMetadata, "Required metadata is missing: manifest.json");
        var iconRecord = records.FirstOrDefault(record => record.Path == "icon.png")
            ?? throw new BundlePackException(BundlePackError.MissingMetadata, "Required metadata is missing: icon.png");
        var animationRecord = records.FirstOrDefault(record => record.Path == BundlePackConstants.AnimationPath);

        if (manifestRecord.CompressionMethod != 0 || manifestRecord.UncompressedSize > BundlePackConstants.MaximumMetadataSize)
        {
            throw new BundlePackException(BundlePackError.UnsupportedCompression, "manifest.json must be stored without compression.");
        }

        if (iconRecord.CompressionMethod != 0 || iconRecord.UncompressedSize > BundlePackConstants.MaximumMetadataSize)
        {
            throw new BundlePackException(BundlePackError.UnsupportedCompression, "icon.png must be stored without compression.");
        }

        if (animationRecord is not null
            && (animationRecord.CompressionMethod != 0
                || animationRecord.UncompressedSize > BundlePackConstants.MaximumMetadataSize))
        {
            throw new BundlePackException(
                BundlePackError.UnsupportedCompression,
                $"{BundlePackConstants.AnimationPath} must be stored without compression.");
        }

        try
        {
            await using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                128 * 1_024,
                FileOptions.Asynchronous | FileOptions.RandomAccess);
            using var archive = new ZipArchive(stream, ZipArchiveMode.Read, leaveOpen: false, entryNameEncoding: StrictUtf8);

            var manifestData = await ReadMetadataAsync(archive, manifestRecord, cancellationToken).ConfigureAwait(false);
            var iconPng = await ReadMetadataAsync(archive, iconRecord, cancellationToken).ConfigureAwait(false);
            BundlePackIcon.ValidatePng(iconPng);

            BundlePackManifest manifest;
            try
            {
                manifest = JsonSerializer.Deserialize<BundlePackManifest>(manifestData, BundlePackJson.Options)
                    ?? throw new JsonException("The manifest is empty.");
            }
            catch (JsonException exception)
            {
                throw new BundlePackException(
                    BundlePackError.InvalidManifest,
                    "manifest.json could not be decoded.",
                    exception);
            }

            if (manifest.Format is null
                || manifest.Title is null
                || manifest.PackageVersion is null
                || manifest.Author is null
                || manifest.Summary is null
                || manifest.Files is null
                || manifest.Files.Any(file => file is null || file.Path is null))
            {
                throw new BundlePackException(BundlePackError.InvalidManifest, "manifest.json contains a null required value.");
            }

            if (manifest.Format != BundlePackConstants.FormatIdentifier)
            {
                throw new BundlePackException(BundlePackError.UnsupportedFormat, "This BundlePack version is not supported.");
            }

            var hasValidAnimationLayout = manifest.FormatVersion switch
            {
                BundlePackConstants.FormatVersion => manifest.Animation is null && animationRecord is null,
                BundlePackConstants.AnimatedFormatVersion =>
                    manifest.Animation is not null
                    && manifest.Animation.Path == BundlePackConstants.AnimationPath
                    && manifest.Animation.MediaType == BundlePackConstants.AnimationMediaType
                    && animationRecord is not null,
                _ => throw new BundlePackException(
                    BundlePackError.UnsupportedFormat,
                    "This BundlePack version is not supported.")
            };
            if (!hasValidAnimationLayout)
            {
                throw new BundlePackException(
                    BundlePackError.InvalidManifest,
                    "The animation metadata does not match the package contents.");
            }

            if (!FileHelpers.HasValidDisplayMetadata(
                    manifest.Title,
                    manifest.PackageVersion,
                    manifest.Author,
                    manifest.Summary))
            {
                throw new BundlePackException(
                    BundlePackError.InvalidManifest,
                    "Package display metadata is too long or contains control characters.");
            }

            var payloadFiles = records
                .Where(record => record.Path.StartsWith("payload/", StringComparison.Ordinal)
                    && !record.Path.EndsWith('/'))
                .Select(record => new BundlePackFile(
                    record.Path["payload/".Length..],
                    record.UncompressedSize))
                .OrderBy(file => file.Path, StringComparer.OrdinalIgnoreCase)
                .ToArray();
            ValidateManifestFiles(manifest, payloadFiles);
            byte[]? animationGif = null;
            if (animationRecord is not null)
            {
                animationGif = await ReadMetadataAsync(archive, animationRecord, cancellationToken).ConfigureAwait(false);
                BundlePackAnimation.ValidateGif(animationGif);
            }
            var expandedSize = records.Aggregate<ZipEntryRecord, ulong>(0, (current, record) => current + record.UncompressedSize);

            return new BundlePackArchiveInfo(
                path,
                manifest,
                iconPng,
                payloadFiles,
                checked((ulong)new FileInfo(path).Length),
                expandedSize,
                animationGif);
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

    internal static async Task CreateAsync(
        string stagingDirectory,
        string archivePath,
        CancellationToken cancellationToken,
        Action<double>? reportProgress = null)
    {
        FileHelpers.TryDeleteFile(archivePath);
        try
        {
            var writeState = new ArchiveWriteState(CalculateArchiveInputBytes(stagingDirectory));
            reportProgress?.Invoke(0);
            await using var stream = new FileStream(
                archivePath,
                FileMode.CreateNew,
                FileAccess.ReadWrite,
                FileShare.None,
                128 * 1_024,
                FileOptions.Asynchronous);
            using var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true, entryNameEncoding: StrictUtf8);

            await AddFileAsync(
                archive,
                Path.Combine(stagingDirectory, "icon.png"),
                "icon.png",
                CompressionLevel.NoCompression,
                cancellationToken,
                writeState,
                reportProgress).ConfigureAwait(false);
            await AddFileAsync(
                archive,
                Path.Combine(stagingDirectory, "manifest.json"),
                "manifest.json",
                CompressionLevel.NoCompression,
                cancellationToken,
                writeState,
                reportProgress).ConfigureAwait(false);
            var animationPath = Path.Combine(stagingDirectory, BundlePackConstants.AnimationPath);
            if (File.Exists(animationPath))
            {
                await AddFileAsync(
                    archive,
                    animationPath,
                    BundlePackConstants.AnimationPath,
                    CompressionLevel.NoCompression,
                    cancellationToken,
                    writeState,
                    reportProgress).ConfigureAwait(false);
            }

            var payloadDirectory = Path.Combine(stagingDirectory, "payload");
            archive.CreateEntry("payload/", CompressionLevel.NoCompression).ExternalAttributes = 0;
            await AddDirectoryAsync(
                archive,
                payloadDirectory,
                "payload",
                cancellationToken,
                writeState,
                reportProgress).ConfigureAwait(false);
            reportProgress?.Invoke(1);
        }
        catch (OperationCanceledException)
        {
            FileHelpers.TryDeleteFile(archivePath);
            throw;
        }
        catch (Exception exception)
        {
            FileHelpers.TryDeleteFile(archivePath);
            throw new BundlePackException(BundlePackError.WriteFailed, "The ZIP archive could not be created.", exception);
        }
    }

    private static long CalculateArchiveInputBytes(string stagingDirectory) =>
        Directory.EnumerateFiles(stagingDirectory, "*", SearchOption.AllDirectories)
            .Sum(path => new FileInfo(path).Length);

    private sealed class ArchiveWriteState(long totalBytes)
    {
        public long TotalBytes { get; } = totalBytes;
        public long WrittenBytes { get; set; }
    }

    internal static async Task<string> ExtractPayloadAsync(
        BundlePackArchiveInfo info,
        string parentDirectory,
        CancellationToken cancellationToken,
        Action<double>? reportProgress = null)
    {
        var records = await ParseAndValidateAsync(info.Path, cancellationToken).ConfigureAwait(false);
        var recordsByPath = records.ToDictionary(record => record.Path, StringComparer.Ordinal);
        Directory.CreateDirectory(parentDirectory);
        var destination = FileHelpers.UniqueDestinationDirectory(parentDirectory, info.Manifest.Title);
        Directory.CreateDirectory(destination);
        var destinationPrefix = Path.GetFullPath(destination) + Path.DirectorySeparatorChar;
        var totalPayloadBytes = info.PayloadFiles.Aggregate<BundlePackFile, ulong>(0, (total, file) => total + file.Size);
        ulong extractedBytes = 0;
        reportProgress?.Invoke(0);

        try
        {
            await using var stream = new FileStream(
                info.Path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                128 * 1_024,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            using var archive = new ZipArchive(stream, ZipArchiveMode.Read, leaveOpen: false, entryNameEncoding: StrictUtf8);

            foreach (var entry in archive.Entries)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (!entry.FullName.StartsWith("payload/", StringComparison.Ordinal))
                {
                    continue;
                }

                var relativePath = entry.FullName["payload/".Length..];
                if (string.IsNullOrEmpty(relativePath))
                {
                    continue;
                }

                var outputPath = Path.GetFullPath(
                    Path.Combine(destination, relativePath.Replace('/', Path.DirectorySeparatorChar)));
                if (!outputPath.StartsWith(destinationPrefix, StringComparison.OrdinalIgnoreCase))
                {
                    throw new BundlePackException(BundlePackError.UnsafeEntry, $"An unsafe path was detected: {entry.FullName}");
                }

                if (entry.FullName.EndsWith('/'))
                {
                    Directory.CreateDirectory(outputPath);
                    continue;
                }

                if (!recordsByPath.TryGetValue(entry.FullName, out var record))
                {
                    throw new BundlePackException(BundlePackError.InvalidEntry, $"A ZIP entry is missing: {entry.FullName}");
                }

                Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
                await using var output = new FileStream(
                    outputPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None,
                    128 * 1_024,
                    FileOptions.Asynchronous | FileOptions.SequentialScan);
                await CopyAndValidateEntryAsync(
                    entry,
                    record,
                    output,
                    cancellationToken,
                    bytes =>
                    {
                        extractedBytes += bytes;
                        reportProgress?.Invoke(totalPayloadBytes == 0
                            ? 1
                            : Math.Clamp((double)extractedBytes / totalPayloadBytes, 0, 1));
                    }).ConfigureAwait(false);
            }

            reportProgress?.Invoke(1);
            return destination;
        }
        catch
        {
            FileHelpers.TryDeleteDirectory(destination);
            throw;
        }
    }
}
