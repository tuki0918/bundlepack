using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace BundlePack.Core;

public static partial class EncryptedContainer
{
    private static async Task<ParsedHeader> ParseHeaderAsync(
        string path,
        CancellationToken cancellationToken)
    {
        try
        {
            var fileLength = new FileInfo(path).Length;
            if (fileLength < FixedHeaderSize)
            {
                throw InvalidContainer();
            }

            await using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                128 * 1_024,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            var headerData = new byte[FixedHeaderSize];
            await FileHelpers.ReadExactlyAsync(stream, headerData, cancellationToken).ConfigureAwait(false);

            if (!headerData.AsSpan(0, Magic.Length).SequenceEqual(Magic))
            {
                throw InvalidContainer();
            }

            var version = BinaryPrimitives.ReadUInt16LittleEndian(headerData.AsSpan(8, 2));
            var flags = BinaryPrimitives.ReadUInt16LittleEndian(headerData.AsSpan(10, 2));
            if (version != Version || flags != Flags)
            {
                throw new BundlePackException(
                    BundlePackError.UnsupportedVersion,
                    "This encrypted BundlePack version is not supported.");
            }

            var header = new Header(
                BinaryPrimitives.ReadUInt32LittleEndian(headerData.AsSpan(12, 4)),
                BinaryPrimitives.ReadUInt32LittleEndian(headerData.AsSpan(16, 4)),
                BinaryPrimitives.ReadUInt32LittleEndian(headerData.AsSpan(20, 4)),
                BinaryPrimitives.ReadUInt64LittleEndian(headerData.AsSpan(24, 8)),
                BinaryPrimitives.ReadUInt32LittleEndian(headerData.AsSpan(32, 4)),
                headerData.AsSpan(36, SaltSize).ToArray(),
                headerData.AsSpan(52, NoncePrefixSize).ToArray(),
                headerData.AsSpan(60, IconHashSize).ToArray());

            if (header.Iterations < MinimumIterations
                || header.Iterations > MaximumIterations
                || header.ChunkSize < MinimumChunkSize
                || header.ChunkSize > MaximumChunkSize
                || header.PlaintextSize == 0
                || header.PlaintextSize > (ulong)BundlePackConstants.MaximumExpandedSize
                || header.IconSize == 0
                || header.IconSize > BundlePackConstants.MaximumMetadataSize)
            {
                throw InvalidContainer();
            }

            var expectedChunkCount = (header.PlaintextSize + header.ChunkSize - 1UL) / header.ChunkSize;
            if (expectedChunkCount != header.ChunkCount)
            {
                throw InvalidContainer();
            }

            ulong expectedFileSize;
            try
            {
                expectedFileSize = checked(
                    (ulong)FixedHeaderSize
                    + header.IconSize
                    + header.PlaintextSize
                    + (ulong)header.ChunkCount * AuthenticationTagSize);
            }
            catch (OverflowException)
            {
                throw InvalidContainer();
            }

            if ((ulong)fileLength != expectedFileSize)
            {
                throw InvalidContainer();
            }

            var iconPng = new byte[checked((int)header.IconSize)];
            await FileHelpers.ReadExactlyAsync(stream, iconPng, cancellationToken).ConfigureAwait(false);
            if (!CryptographicOperations.FixedTimeEquals(SHA256.HashData(iconPng), header.IconHash))
            {
                throw new BundlePackException(BundlePackError.InvalidIcon, "The public package icon is invalid.");
            }

            BundlePackIcon.ValidatePng(iconPng);
            return new ParsedHeader(header, headerData, iconPng, checked((ulong)fileLength));
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
                BundlePackError.InvalidContainer,
                "The file is not an encrypted BundlePack or is damaged.",
                exception);
        }
    }

    private static byte[] EncodeHeader(Header header)
    {
        var data = new byte[FixedHeaderSize];
        Magic.CopyTo(data, 0);
        BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(8, 2), Version);
        BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(10, 2), Flags);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(12, 4), header.Iterations);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(16, 4), header.ChunkSize);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(20, 4), header.ChunkCount);
        BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(24, 8), header.PlaintextSize);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(32, 4), header.IconSize);
        header.Salt.CopyTo(data, 36);
        header.NoncePrefix.CopyTo(data, 52);
        header.IconHash.CopyTo(data, 60);
        return data;
    }

    private static byte[] DeriveKey(string password, byte[] salt, uint iterations)
    {
        try
        {
            var normalizedPassword = FileHelpers.NormalizePassword(password);
            var passwordBytes = Encoding.UTF8.GetBytes(normalizedPassword);
            try
            {
                return Rfc2898DeriveBytes.Pbkdf2(
                    passwordBytes,
                    salt,
                    checked((int)iterations),
                    HashAlgorithmName.SHA256,
                    32);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(passwordBytes);
            }
        }
        catch (Exception exception) when (exception is not BundlePackException)
        {
            throw new BundlePackException(
                BundlePackError.KeyDerivationFailed,
                "The encryption key could not be derived.",
                exception);
        }
    }

    private static byte[] CreateNonce(byte[] prefix, uint index)
    {
        var nonce = new byte[12];
        prefix.CopyTo(nonce, 0);
        BinaryPrimitives.WriteUInt32LittleEndian(nonce.AsSpan(8, 4), index);
        return nonce;
    }

    private static byte[] CreateAuthenticatedData(byte[] headerData, uint index)
    {
        var data = new byte[headerData.Length + 4];
        headerData.CopyTo(data, 0);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(headerData.Length, 4), index);
        return data;
    }

    private static int PlaintextLength(uint index, Header header)
    {
        var consumed = (ulong)index * header.ChunkSize;
        return checked((int)Math.Min(header.ChunkSize, header.PlaintextSize - consumed));
    }

    private static BundlePackException InvalidContainer() => new(
        BundlePackError.InvalidContainer,
        "The file is not an encrypted BundlePack or is damaged.");

    private sealed record Header(
        uint Iterations,
        uint ChunkSize,
        uint ChunkCount,
        ulong PlaintextSize,
        uint IconSize,
        byte[] Salt,
        byte[] NoncePrefix,
        byte[] IconHash);

    private sealed record ParsedHeader(
        Header Header,
        byte[] HeaderData,
        byte[] IconPng,
        ulong FileSize);
}
