using System.Text.Json.Serialization;

namespace BundlePack.Core;

public sealed record BundlePackFile(
    [property: JsonPropertyName("path")] string Path,
    [property: JsonPropertyName("size")] ulong Size);

public sealed record BundlePackOperationProgress
{
    public BundlePackOperationProgress(double fractionCompleted, string message)
    {
        FractionCompleted = Math.Clamp(fractionCompleted, 0, 1);
        Message = message;
    }

    public double FractionCompleted { get; }
    public string Message { get; }
}

public sealed class BundlePackManifest
{
    [JsonPropertyName("format")]
    public required string Format { get; init; }

    [JsonPropertyName("formatVersion")]
    public required int FormatVersion { get; init; }

    [JsonPropertyName("title")]
    public required string Title { get; init; }

    [JsonPropertyName("packageVersion")]
    public required string PackageVersion { get; init; }

    [JsonPropertyName("author")]
    public required string Author { get; init; }

    [JsonPropertyName("summary")]
    public required string Summary { get; init; }

    [JsonPropertyName("createdAt")]
    public required DateTimeOffset CreatedAt { get; init; }

    [JsonPropertyName("files")]
    public required IReadOnlyList<BundlePackFile> Files { get; init; }
}

public sealed record PackageCreationRequest(
    string Title,
    string PackageVersion,
    string Author,
    string Summary,
    IReadOnlyList<string> InputPaths,
    byte[] IconPng,
    bool EncryptionEnabled,
    string Password,
    string DestinationPath);

public sealed record EncryptedBundlePackInfo(
    string Path,
    byte[] IconPng,
    ulong EncryptedSize,
    ulong OriginalArchiveSize);

public sealed record BundlePackArchiveInfo(
    string Path,
    BundlePackManifest Manifest,
    byte[] IconPng,
    IReadOnlyList<BundlePackFile> PayloadFiles,
    ulong ArchiveSize,
    ulong ExpandedSize);

public sealed class OpenedBundlePack : IDisposable
{
    private int _disposed;
    internal OpenedBundlePack(
        string sourcePath,
        bool isEncrypted,
        byte[] iconPng,
        ulong originalArchiveSize,
        BundlePackArchiveInfo? archive,
        string? temporaryArchivePath)
    {
        SourcePath = sourcePath;
        IsEncrypted = isEncrypted;
        IconPng = iconPng;
        OriginalArchiveSize = originalArchiveSize;
        Archive = archive;
        TemporaryArchivePath = temporaryArchivePath;
    }

    public string SourcePath { get; }
    public bool IsEncrypted { get; }
    public bool IsUnlocked => Archive is not null;
    public byte[] IconPng { get; }
    public ulong OriginalArchiveSize { get; }
    public BundlePackArchiveInfo? Archive { get; }

    internal string? TemporaryArchivePath { get; }

    ~OpenedBundlePack()
    {
        Dispose(disposing: false);
    }

    public void Dispose()
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);
    }

    private void Dispose(bool disposing)
    {
        if (Interlocked.Exchange(ref _disposed, 1) == 0 && TemporaryArchivePath is not null)
        {
            FileHelpers.TryDeleteFile(TemporaryArchivePath);
        }
    }
}
