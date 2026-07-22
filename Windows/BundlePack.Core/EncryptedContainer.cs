using System.Security.Cryptography;

namespace BundlePack.Core;

public static partial class EncryptedContainer
{
    private static readonly byte[] Magic = "BPKENC01"u8.ToArray();

    private const ushort Version = 1;
    private const ushort Flags = 1;
    private const int FixedHeaderSize = 92;
    private const int SaltSize = 16;
    private const int NoncePrefixSize = 8;
    private const int IconHashSize = 32;
    private const int AuthenticationTagSize = 16;
    private const uint MinimumIterations = 100_000;
    private const uint MaximumIterations = 5_000_000;
    private const uint MinimumChunkSize = 64 * 1_024;
    private const uint MaximumChunkSize = 16 * 1_024 * 1_024;

    public static bool IsEncrypted(string path)
    {
        try
        {
            Span<byte> bytes = stackalloc byte[8];
            using var stream = File.OpenRead(path);
            return stream.Read(bytes) == bytes.Length && bytes.SequenceEqual(Magic);
        }
        catch
        {
            return false;
        }
    }

    public static async Task<EncryptedBundlePackInfo> ReadPublicInfoAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        var parsed = await ParseHeaderAsync(path, cancellationToken).ConfigureAwait(false);
        return new EncryptedBundlePackInfo(
            path,
            parsed.IconPng,
            parsed.FileSize,
            parsed.Header.PlaintextSize);
    }

    public static async Task<EncryptedBundlePackInfo> SealAsync(
        string archivePath,
        byte[] iconPng,
        string password,
        string destinationPath,
        CancellationToken cancellationToken = default,
        Action<double>? reportProgress = null)
    {
        if (!FileHelpers.HasMinimumPasswordLength(password))
        {
            throw new BundlePackException(
                BundlePackError.PasswordTooShort,
                $"The password must contain at least {BundlePackConstants.MinimumPasswordCharacters} characters.");
        }

        BundlePackIcon.ValidatePng(iconPng);

        var archiveLength = new FileInfo(archivePath).Length;
        if (archiveLength <= 0 || archiveLength > BundlePackConstants.MaximumExpandedSize)
        {
            throw new BundlePackException(BundlePackError.ContainerTooLarge, "The encrypted package exceeds the safety limit.");
        }

        var plaintextSize = checked((ulong)archiveLength);
        var chunkCount64 = (plaintextSize + BundlePackConstants.PlaintextChunkSize - 1UL)
            / BundlePackConstants.PlaintextChunkSize;
        if (chunkCount64 == 0 || chunkCount64 > uint.MaxValue)
        {
            throw new BundlePackException(BundlePackError.ContainerTooLarge, "The encrypted package exceeds the safety limit.");
        }

        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var noncePrefix = RandomNumberGenerator.GetBytes(NoncePrefixSize);
        var iconHash = SHA256.HashData(iconPng);
        var header = new Header(
            BundlePackConstants.Pbkdf2Iterations,
            BundlePackConstants.PlaintextChunkSize,
            checked((uint)chunkCount64),
            plaintextSize,
            checked((uint)iconPng.Length),
            salt,
            noncePrefix,
            iconHash);
        var headerData = EncodeHeader(header);
        var key = DeriveKey(password, salt, header.Iterations);

        var destinationDirectory = Path.GetDirectoryName(Path.GetFullPath(destinationPath))
            ?? throw new BundlePackException(BundlePackError.WriteFailed, "The destination folder is invalid.");
        Directory.CreateDirectory(destinationDirectory);
        var temporaryPath = Path.Combine(
            destinationDirectory,
            $".{Path.GetFileName(destinationPath)}.{Guid.NewGuid():N}.tmp");

        try
        {
            await using var input = new FileStream(
                archivePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                128 * 1_024,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            await using var output = new FileStream(
                temporaryPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                128 * 1_024,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            using var aes = new AesGcm(key, AuthenticationTagSize);

            await output.WriteAsync(headerData, cancellationToken).ConfigureAwait(false);
            await output.WriteAsync(iconPng, cancellationToken).ConfigureAwait(false);
            reportProgress?.Invoke(0);

            for (uint index = 0; index < header.ChunkCount; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var length = PlaintextLength(index, header);
                var plaintext = new byte[length];
                var ciphertext = new byte[length];
                var tag = new byte[AuthenticationTagSize];
                try
                {
                    await FileHelpers.ReadExactlyAsync(input, plaintext, cancellationToken).ConfigureAwait(false);
                    var nonce = CreateNonce(header.NoncePrefix, index);
                    var authenticatedData = CreateAuthenticatedData(headerData, index);
                    aes.Encrypt(nonce, plaintext, ciphertext, tag, authenticatedData);
                    await output.WriteAsync(ciphertext, cancellationToken).ConfigureAwait(false);
                    await output.WriteAsync(tag, cancellationToken).ConfigureAwait(false);
                    reportProgress?.Invoke((double)(index + 1) / header.ChunkCount);
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(plaintext);
                    CryptographicOperations.ZeroMemory(ciphertext);
                    CryptographicOperations.ZeroMemory(tag);
                }
            }

            await output.FlushAsync(cancellationToken).ConfigureAwait(false);
            output.Close();
            File.Move(temporaryPath, destinationPath, overwrite: true);
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
            throw new BundlePackException(
                BundlePackError.WriteFailed,
                "The encrypted package could not be written.",
                exception);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
            FileHelpers.TryDeleteFile(temporaryPath);
        }

        return await ReadPublicInfoAsync(destinationPath, cancellationToken).ConfigureAwait(false);
    }

    public static async Task OpenAsync(
        string encryptedPath,
        string password,
        string archiveDestinationPath,
        CancellationToken cancellationToken = default,
        Action<double>? reportProgress = null)
    {
        if (!FileHelpers.HasMinimumPasswordLength(password))
        {
            throw new BundlePackException(
                BundlePackError.PasswordTooShort,
                $"The password must contain at least {BundlePackConstants.MinimumPasswordCharacters} characters.");
        }

        var parsed = await ParseHeaderAsync(encryptedPath, cancellationToken).ConfigureAwait(false);
        var key = DeriveKey(password, parsed.Header.Salt, parsed.Header.Iterations);
        FileHelpers.TryDeleteFile(archiveDestinationPath);

        try
        {
            await using var input = new FileStream(
                encryptedPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                128 * 1_024,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            await using var output = new FileStream(
                archiveDestinationPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                128 * 1_024,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            using var aes = new AesGcm(key, AuthenticationTagSize);
            input.Position = checked(FixedHeaderSize + parsed.Header.IconSize);
            reportProgress?.Invoke(0);

            for (uint index = 0; index < parsed.Header.ChunkCount; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var length = PlaintextLength(index, parsed.Header);
                var ciphertext = new byte[length];
                var plaintext = new byte[length];
                var tag = new byte[AuthenticationTagSize];
                try
                {
                    await FileHelpers.ReadExactlyAsync(input, ciphertext, cancellationToken).ConfigureAwait(false);
                    await FileHelpers.ReadExactlyAsync(input, tag, cancellationToken).ConfigureAwait(false);
                    var nonce = CreateNonce(parsed.Header.NoncePrefix, index);
                    var authenticatedData = CreateAuthenticatedData(parsed.HeaderData, index);
                    aes.Decrypt(nonce, ciphertext, tag, plaintext, authenticatedData);
                    await output.WriteAsync(plaintext, cancellationToken).ConfigureAwait(false);
                    reportProgress?.Invoke((double)(index + 1) / parsed.Header.ChunkCount);
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(ciphertext);
                    CryptographicOperations.ZeroMemory(plaintext);
                    CryptographicOperations.ZeroMemory(tag);
                }
            }

            await output.FlushAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            FileHelpers.TryDeleteFile(archiveDestinationPath);
            throw;
        }
        catch (CryptographicException exception)
        {
            FileHelpers.TryDeleteFile(archiveDestinationPath);
            throw new BundlePackException(
                BundlePackError.WrongPasswordOrTampered,
                "The password is incorrect, or the package has been modified or damaged.",
                exception);
        }
        catch (BundlePackException)
        {
            FileHelpers.TryDeleteFile(archiveDestinationPath);
            throw;
        }
        catch (Exception exception)
        {
            FileHelpers.TryDeleteFile(archiveDestinationPath);
            throw new BundlePackException(
                BundlePackError.InvalidContainer,
                "The file is not an encrypted BundlePack or is damaged.",
                exception);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }
}
