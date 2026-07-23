using System.Security.Cryptography;
using System.Text.Json;

namespace BundlePack.Core;

public static partial class BundlePackService
{
    public static async Task<OpenedBundlePack> CreateAsync(
        PackageCreationRequest request,
        CancellationToken cancellationToken = default,
        IProgress<BundlePackOperationProgress>? progress = null)
    {
        ReportProgress(progress, 0, "Preparing files…");
        if (request.InputPaths.Count == 0)
        {
            throw new BundlePackException(BundlePackError.NoInputFiles, "Choose at least one file or folder to include.");
        }

        if (request.EncryptionEnabled && !FileHelpers.HasMinimumPasswordLength(request.Password))
        {
            throw new BundlePackException(
                BundlePackError.PasswordTooShort,
                $"The password must contain at least {BundlePackConstants.MinimumPasswordCharacters} characters.");
        }

        BundlePackIcon.ValidatePng(request.IconPng);
        if (request.AnimationGif is not null)
        {
            BundlePackAnimation.ValidateGif(request.AnimationGif);
        }
        var normalizedTitle = string.IsNullOrWhiteSpace(request.Title) ? "Untitled Package" : request.Title.Trim();
        var normalizedVersion = request.PackageVersion.Trim();
        var normalizedAuthor = request.Author.Trim();
        var normalizedSummary = request.Summary.Trim();
        if (!FileHelpers.HasValidDisplayMetadata(
                normalizedTitle,
                normalizedVersion,
                normalizedAuthor,
                normalizedSummary))
        {
            throw new BundlePackException(
                BundlePackError.InvalidManifest,
                "Package metadata is too long or contains unsupported control characters.");
        }
        var root = Path.Combine(Path.GetTempPath(), $"BundlePack-{Guid.NewGuid():N}");
        var staging = Path.Combine(root, "staging");
        var payload = Path.Combine(staging, "payload");
        var archivePath = Path.Combine(root, "archive.zip");
        Directory.CreateDirectory(payload);

        try
        {
            var totalInputBytes = CalculateTotalInputBytes(request.InputPaths, cancellationToken);
            var usedNames = new HashSet<string>(FileHelpers.OutputPathComparer);
            var copyState = new CopyState();
            foreach (var sourcePath in request.InputPaths)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var fullSourcePath = Path.GetFullPath(sourcePath);
                ValidateInputExists(fullSourcePath);
                var originalName = Path.GetFileName(fullSourcePath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
                var uniqueName = UniqueName(originalName, usedNames);
                await CopyInputAsync(
                    fullSourcePath,
                    Path.Combine(payload, uniqueName),
                    copyState,
                    cancellationToken,
                    copiedBytes => ReportProgress(
                        progress,
                        0.05 + (totalInputBytes == 0 ? 1 : (double)copiedBytes / totalInputBytes) * 0.4,
                        "Copying files…")).ConfigureAwait(false);
            }

            ReportProgress(progress, 0.45, "Preparing package metadata…");

            var files = Directory.EnumerateFiles(payload, "*", SearchOption.AllDirectories)
                .Select(path => new BundlePackFile(
                    Path.GetRelativePath(payload, path).Replace('\\', '/'),
                    checked((ulong)new FileInfo(path).Length)))
                .OrderBy(file => file.Path, StringComparer.OrdinalIgnoreCase)
                .ToArray();
            var manifest = new BundlePackManifest
            {
                Format = BundlePackConstants.FormatIdentifier,
                FormatVersion = request.AnimationGif is null
                    ? BundlePackConstants.FormatVersion
                    : BundlePackConstants.AnimatedFormatVersion,
                Title = normalizedTitle,
                PackageVersion = normalizedVersion,
                Author = normalizedAuthor,
                Summary = normalizedSummary,
                CreatedAt = DateTimeOffset.UtcNow,
                Files = files,
                Animation = request.AnimationGif is null
                    ? null
                    : new BundlePackAnimationMetadata(
                        BundlePackConstants.AnimationPath,
                        BundlePackConstants.AnimationMediaType)
            };
            var manifestData = JsonSerializer.SerializeToUtf8Bytes(manifest, BundlePackJson.Options);
            await File.WriteAllBytesAsync(Path.Combine(staging, "manifest.json"), manifestData, cancellationToken)
                .ConfigureAwait(false);
            await File.WriteAllBytesAsync(Path.Combine(staging, "icon.png"), request.IconPng, cancellationToken)
                .ConfigureAwait(false);
            if (request.AnimationGif is not null)
            {
                await File.WriteAllBytesAsync(
                    Path.Combine(staging, BundlePackConstants.AnimationPath),
                    request.AnimationGif,
                    cancellationToken).ConfigureAwait(false);
            }
            await BundlePackArchive.CreateAsync(
                staging,
                archivePath,
                cancellationToken,
                fraction => ReportProgress(progress, 0.5 + fraction * 0.22, "Compressing files…"))
                .ConfigureAwait(false);

            if (request.EncryptionEnabled)
            {
                await EncryptedContainer.SealAsync(
                    archivePath,
                    request.IconPng,
                    request.Password,
                    request.DestinationPath,
                    cancellationToken,
                    fraction => ReportProgress(progress, 0.74 + fraction * 0.25, "Encrypting package…"))
                    .ConfigureAwait(false);
            }
            else
            {
                await InstallUnencryptedArchiveAsync(
                    archivePath,
                    request.DestinationPath,
                    cancellationToken,
                    fraction => ReportProgress(progress, 0.74 + fraction * 0.25, "Writing package…"))
                    .ConfigureAwait(false);
            }

            var result = await OpenAsync(request.DestinationPath, password: null, cancellationToken).ConfigureAwait(false);
            ReportProgress(progress, 1, "Package created");
            return result;
        }
        finally
        {
            FileHelpers.TryDeleteDirectory(root);
        }
    }

    public static async Task<OpenedBundlePack> OpenAsync(
        string path,
        string? password = null,
        CancellationToken cancellationToken = default,
        IProgress<BundlePackOperationProgress>? progress = null)
    {
        ReportProgress(progress, 0, "Reading package…");
        var fullPath = Path.GetFullPath(path);
        if (EncryptedContainer.IsEncrypted(fullPath))
        {
            var publicInfo = await EncryptedContainer.ReadPublicInfoAsync(fullPath, cancellationToken).ConfigureAwait(false);
            if (password is null)
            {
                ReportProgress(progress, 1, "Encrypted package ready to unlock");
                return new OpenedBundlePack(
                    fullPath,
                    isEncrypted: true,
                    publicInfo.IconPng,
                    publicInfo.OriginalArchiveSize,
                    archive: null,
                    temporaryArchivePath: null);
            }

            var temporaryArchivePath = Path.Combine(
                Path.GetTempPath(),
                $"BundlePack-Decrypted-{Guid.NewGuid():N}.zip");
            try
            {
                await EncryptedContainer.OpenAsync(
                    fullPath,
                    password,
                    temporaryArchivePath,
                    cancellationToken,
                    fraction => ReportProgress(progress, 0.08 + fraction * 0.72, "Decrypting package…"))
                    .ConfigureAwait(false);
                ReportProgress(progress, 0.82, "Validating decrypted contents…");
                var archive = await BundlePackArchive.InspectAsync(temporaryArchivePath, cancellationToken).ConfigureAwait(false);
                if (!CryptographicOperations.FixedTimeEquals(publicInfo.IconPng, archive.IconPng))
                {
                    throw new BundlePackException(BundlePackError.InvalidIcon, "The public and encrypted package icons do not match.");
                }

                var result = new OpenedBundlePack(
                    fullPath,
                    isEncrypted: true,
                    publicInfo.IconPng,
                    publicInfo.OriginalArchiveSize,
                    archive,
                    temporaryArchivePath);
                ReportProgress(progress, 1, "Decrypted and validated");
                return result;
            }
            catch
            {
                FileHelpers.TryDeleteFile(temporaryArchivePath);
                throw;
            }
        }

        var snapshotPath = Path.Combine(Path.GetTempPath(), $"BundlePack-Opened-{Guid.NewGuid():N}.zip");
        try
        {
            await CopyStableSnapshotAsync(
                fullPath,
                snapshotPath,
                cancellationToken,
                fraction => ReportProgress(progress, fraction * 0.65, "Creating a safe snapshot…"))
                .ConfigureAwait(false);
            ReportProgress(progress, 0.72, "Validating package…");
            var unencryptedArchive = await BundlePackArchive.InspectAsync(snapshotPath, cancellationToken).ConfigureAwait(false);
            var result = new OpenedBundlePack(
                fullPath,
                isEncrypted: false,
                unencryptedArchive.IconPng,
                unencryptedArchive.ArchiveSize,
                unencryptedArchive,
                snapshotPath);
            ReportProgress(progress, 1, "Package validated");
            return result;
        }
        catch
        {
            FileHelpers.TryDeleteFile(snapshotPath);
            throw;
        }
    }

    public static async Task<string> ExtractAsync(
        OpenedBundlePack package,
        string parentDirectory,
        CancellationToken cancellationToken = default,
        IProgress<BundlePackOperationProgress>? progress = null)
    {
        ReportProgress(progress, 0, "Preparing extraction…");
        var archive = package.Archive
            ?? throw new BundlePackException(BundlePackError.InvalidContainer, "Unlock the encrypted package before extracting it.");
        var destination = await BundlePackArchive.ExtractPayloadAsync(
            archive,
            parentDirectory,
            cancellationToken,
            fraction => ReportProgress(progress, 0.05 + fraction * 0.94, "Extracting files…"))
            .ConfigureAwait(false);
        ReportProgress(progress, 1, "Extraction complete");
        return destination;
    }

    private static void ReportProgress(
        IProgress<BundlePackOperationProgress>? progress,
        double fraction,
        string message) =>
        progress?.Report(new BundlePackOperationProgress(fraction, message));
}
