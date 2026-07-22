namespace BundlePack.Core;

public static partial class BundlePackService
{
    private static void ValidateInputExists(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path))
        {
            throw new FileNotFoundException("An input file or folder no longer exists.", path);
        }
    }

    private static async Task InstallUnencryptedArchiveAsync(
        string archivePath,
        string destinationPath,
        CancellationToken cancellationToken,
        Action<double>? reportProgress = null)
    {
        var fullDestinationPath = Path.GetFullPath(destinationPath);
        var destinationDirectory = Path.GetDirectoryName(fullDestinationPath)
            ?? throw new BundlePackException(BundlePackError.WriteFailed, "The destination folder is invalid.");
        Directory.CreateDirectory(destinationDirectory);
        var temporaryPath = Path.Combine(
            destinationDirectory,
            $".{Path.GetFileName(fullDestinationPath)}.{Guid.NewGuid():N}.tmp");

        try
        {
            await using (var input = new FileStream(
                archivePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                128 * 1_024,
                FileOptions.Asynchronous | FileOptions.SequentialScan))
            await using (var output = new FileStream(
                temporaryPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                128 * 1_024,
                FileOptions.Asynchronous | FileOptions.SequentialScan))
            {
                await CopyStreamAsync(input, output, input.Length, cancellationToken, reportProgress).ConfigureAwait(false);
                await output.FlushAsync(cancellationToken).ConfigureAwait(false);
            }

            File.Move(temporaryPath, fullDestinationPath, overwrite: true);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new BundlePackException(
                BundlePackError.WriteFailed,
                "The unencrypted package could not be written.",
                exception);
        }
        finally
        {
            FileHelpers.TryDeleteFile(temporaryPath);
        }
    }

    private static async Task CopyStableSnapshotAsync(
        string sourcePath,
        string snapshotPath,
        CancellationToken cancellationToken,
        Action<double>? reportProgress = null)
    {
        await using var input = new FileStream(
            sourcePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            128 * 1_024,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        await using var output = new FileStream(
            snapshotPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            128 * 1_024,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        await CopyStreamAsync(input, output, input.Length, cancellationToken, reportProgress).ConfigureAwait(false);
        await output.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task CopyStreamAsync(
        Stream input,
        Stream output,
        long totalBytes,
        CancellationToken cancellationToken,
        Action<double>? reportProgress)
    {
        var buffer = new byte[128 * 1_024];
        long copied = 0;
        while (true)
        {
            var count = await input.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            if (count == 0)
            {
                break;
            }

            await output.WriteAsync(buffer.AsMemory(0, count), cancellationToken).ConfigureAwait(false);
            copied += count;
            reportProgress?.Invoke(totalBytes == 0 ? 1 : Math.Clamp((double)copied / totalBytes, 0, 1));
        }

        if (totalBytes == 0)
        {
            reportProgress?.Invoke(1);
        }
    }

    private static long CalculateTotalInputBytes(
        IReadOnlyList<string> inputPaths,
        CancellationToken cancellationToken)
    {
        long total = 0;
        foreach (var inputPath in inputPaths)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var fullPath = Path.GetFullPath(inputPath);
            ValidateInputExists(fullPath);
            try
            {
                total = checked(total + CalculateInputBytes(fullPath, cancellationToken));
            }
            catch (OverflowException exception)
            {
                throw new BundlePackException(
                    BundlePackError.ArchiveTooLarge,
                    "The expanded size exceeds the safety limit.",
                    exception);
            }
            if (total > BundlePackConstants.MaximumExpandedSize)
            {
                throw new BundlePackException(BundlePackError.ArchiveTooLarge, "The expanded size exceeds the safety limit.");
            }
        }

        return total;
    }

    private static long CalculateInputBytes(string path, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var name = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        if (!FileHelpers.IsPortableFileName(name))
        {
            throw new BundlePackException(
                BundlePackError.UnsafeEntry,
                $"The file name is not portable between macOS and Windows: {name}");
        }

        var attributes = File.GetAttributes(path);
        if ((attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new BundlePackException(BundlePackError.UnsafeEntry, $"Symbolic links cannot be included: {path}");
        }

        if ((attributes & FileAttributes.Directory) == 0)
        {
            var length = new FileInfo(path).Length;
            if (length < 0 || length > BundlePackConstants.MaximumInputFileSize)
            {
                throw new BundlePackException(BundlePackError.ArchiveTooLarge, $"Files of 4 GB or larger are not supported: {path}");
            }
            return length;
        }

        long total = 0;
        foreach (var child in Directory.EnumerateFileSystemEntries(path))
        {
            total = checked(total + CalculateInputBytes(child, cancellationToken));
            if (total > BundlePackConstants.MaximumExpandedSize)
            {
                throw new BundlePackException(BundlePackError.ArchiveTooLarge, "The expanded size exceeds the safety limit.");
            }
        }
        return total;
    }

    private static async Task CopyInputAsync(
        string sourcePath,
        string destinationPath,
        CopyState state,
        CancellationToken cancellationToken,
        Action<long>? didCopy = null)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var name = Path.GetFileName(sourcePath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        if (!FileHelpers.IsPortableFileName(name))
        {
            throw new BundlePackException(
                BundlePackError.UnsafeEntry,
                $"The file name is not portable between macOS and Windows: {name}");
        }

        var attributes = File.GetAttributes(sourcePath);
        if ((attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new BundlePackException(BundlePackError.UnsafeEntry, $"Symbolic links cannot be included: {sourcePath}");
        }

        state.EntryCount++;
        if (state.EntryCount > BundlePackConstants.MaximumEntries - 3)
        {
            throw new BundlePackException(BundlePackError.ArchiveTooLarge, "The file count exceeds the safety limit.");
        }

        if ((attributes & FileAttributes.Directory) != 0)
        {
            Directory.CreateDirectory(destinationPath);
            foreach (var child in Directory.EnumerateFileSystemEntries(sourcePath))
            {
                await CopyInputAsync(
                    child,
                    Path.Combine(destinationPath, Path.GetFileName(child)),
                    state,
                    cancellationToken,
                    didCopy).ConfigureAwait(false);
            }

            return;
        }

        var length = new FileInfo(sourcePath).Length;
        if (length < 0 || length > BundlePackConstants.MaximumInputFileSize)
        {
            throw new BundlePackException(BundlePackError.ArchiveTooLarge, $"Files of 4 GB or larger are not supported: {sourcePath}");
        }

        state.ExpandedSize = checked(state.ExpandedSize + length);
        if (state.ExpandedSize > BundlePackConstants.MaximumExpandedSize)
        {
            throw new BundlePackException(BundlePackError.ArchiveTooLarge, "The expanded size exceeds the safety limit.");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
        await using var input = new FileStream(
            sourcePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            128 * 1_024,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        if (input.Length != length)
        {
            throw new BundlePackException(BundlePackError.UnsafeEntry, $"An input file changed while it was being added: {sourcePath}");
        }
        await using var output = new FileStream(
            destinationPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            128 * 1_024,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        var buffer = new byte[128 * 1_024];
        long copied = 0;
        while (copied < length)
        {
            var requested = checked((int)Math.Min(buffer.Length, length - copied));
            var count = await input.ReadAsync(buffer.AsMemory(0, requested), cancellationToken).ConfigureAwait(false);
            if (count == 0)
            {
                throw new BundlePackException(BundlePackError.UnsafeEntry, $"An input file changed while it was being added: {sourcePath}");
            }
            await output.WriteAsync(buffer.AsMemory(0, count), cancellationToken).ConfigureAwait(false);
            copied += count;
            state.CopiedBytes = checked(state.CopiedBytes + count);
            didCopy?.Invoke(state.CopiedBytes);
        }
        if (await input.ReadAsync(buffer.AsMemory(0, 1), cancellationToken).ConfigureAwait(false) != 0)
        {
            throw new BundlePackException(BundlePackError.ArchiveTooLarge, $"An input file grew while it was being added: {sourcePath}");
        }
        if (length == 0)
        {
            didCopy?.Invoke(state.CopiedBytes);
        }
    }

    private static string UniqueName(string originalName, ISet<string> usedNames)
    {
        var normalizedOriginal = FileHelpers.NormalizeOutputPath(originalName);
        if (usedNames.Add(normalizedOriginal))
        {
            return originalName;
        }

        var extension = Path.GetExtension(originalName);
        var baseName = Path.GetFileNameWithoutExtension(originalName);
        for (var index = 2; ; index++)
        {
            var candidate = $"{baseName} {index}{extension}";
            if (usedNames.Add(FileHelpers.NormalizeOutputPath(candidate)))
            {
                return candidate;
            }
        }
    }

    private sealed class CopyState
    {
        public int EntryCount { get; set; }
        public long ExpandedSize { get; set; }
        public long CopiedBytes { get; set; }
    }
}
