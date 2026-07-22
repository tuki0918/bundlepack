using System.IO.Compression;

namespace BundlePack.Core;

public static partial class BundlePackArchive
{
    private static async Task AddDirectoryAsync(
        ZipArchive archive,
        string directoryPath,
        string archivePath,
        CancellationToken cancellationToken,
        ArchiveWriteState state,
        Action<double>? reportProgress)
    {
        foreach (var itemPath in Directory.EnumerateFileSystemEntries(directoryPath).OrderBy(path => path, StringComparer.OrdinalIgnoreCase))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var name = Path.GetFileName(itemPath);
            var itemArchivePath = $"{archivePath}/{name}";
            if (Directory.Exists(itemPath))
            {
                archive.CreateEntry($"{itemArchivePath}/", CompressionLevel.NoCompression).ExternalAttributes = 0;
                await AddDirectoryAsync(
                    archive,
                    itemPath,
                    itemArchivePath,
                    cancellationToken,
                    state,
                    reportProgress).ConfigureAwait(false);
            }
            else
            {
                await AddFileAsync(
                    archive,
                    itemPath,
                    itemArchivePath,
                    CompressionLevel.Optimal,
                    cancellationToken,
                    state,
                    reportProgress).ConfigureAwait(false);
            }
        }
    }

    private static async Task AddFileAsync(
        ZipArchive archive,
        string filePath,
        string archivePath,
        CompressionLevel compressionLevel,
        CancellationToken cancellationToken,
        ArchiveWriteState state,
        Action<double>? reportProgress)
    {
        var entry = archive.CreateEntry(archivePath.Replace('\\', '/'), compressionLevel);
        entry.ExternalAttributes = 0;
        await using var input = new FileStream(
            filePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            128 * 1_024,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        await using var output = entry.Open();
        var buffer = new byte[128 * 1_024];
        while (true)
        {
            var count = await input.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            if (count == 0)
            {
                break;
            }
            await output.WriteAsync(buffer.AsMemory(0, count), cancellationToken).ConfigureAwait(false);
            state.WrittenBytes = checked(state.WrittenBytes + count);
            reportProgress?.Invoke(state.TotalBytes == 0
                ? 1
                : Math.Clamp((double)state.WrittenBytes / state.TotalBytes, 0, 1));
        }
    }
}
