using System.Buffers.Binary;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Security.Cryptography;
using System.Text;
using BundlePack.Core;

namespace BundlePack.Thumbnail;

internal static class PublicIconReader
{
    private static readonly byte[] EncryptedMagic = "BPKENC01"u8.ToArray();
    private static readonly byte[] PngEntryName = "icon.png"u8.ToArray();
    private const uint LocalFileHeaderSignature = 0x0403_4b50;
    private const int EncryptedHeaderSize = 92;
    private const int MaximumIconSize = 16 * 1_024 * 1_024;
    private static readonly uint[] Crc32Table = CreateCrc32Table();

    public static byte[] Read(IStream stream)
    {
        var prefix = ReadExactly(stream, 0, 8);
        var icon = prefix.SequenceEqual(EncryptedMagic)
            ? ReadEncryptedIcon(stream)
            : ReadZipIcon(stream);
        BundlePackIcon.ValidatePng(icon);
        return icon;
    }

    private static byte[] ReadEncryptedIcon(IStream stream)
    {
        var header = ReadExactly(stream, 0, EncryptedHeaderSize);
        if (!header.AsSpan(0, EncryptedMagic.Length).SequenceEqual(EncryptedMagic)
            || BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(8, 2)) != 1
            || BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(10, 2)) != 1)
        {
            throw new InvalidDataException("The encrypted BundlePack header is invalid.");
        }

        var iconSize = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(32, 4));
        if (iconSize == 0 || iconSize > MaximumIconSize)
        {
            throw new InvalidDataException("The public package icon size is invalid.");
        }

        var icon = ReadExactly(stream, EncryptedHeaderSize, checked((int)iconSize));
        var expectedHash = header.AsSpan(60, 32);
        if (!CryptographicOperations.FixedTimeEquals(SHA256.HashData(icon), expectedHash))
        {
            throw new InvalidDataException("The public package icon hash is invalid.");
        }

        return icon;
    }

    private static byte[] ReadZipIcon(IStream stream)
    {
        var header = ReadExactly(stream, 0, 30);
        if (BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(0, 4)) != LocalFileHeaderSignature)
        {
            throw new InvalidDataException("The BundlePack ZIP header is invalid.");
        }

        var flags = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(6, 2));
        var compressionMethod = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(8, 2));
        var expectedCrc32 = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(14, 4));
        var compressedSize = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(18, 4));
        var uncompressedSize = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(22, 4));
        var nameLength = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(26, 2));
        var extraLength = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(28, 2));
        if ((flags & 0x0009) != 0
            || compressionMethod != 0
            || uncompressedSize == 0
            || uncompressedSize > MaximumIconSize
            || compressedSize != uncompressedSize)
        {
            throw new InvalidDataException("The public package icon entry is invalid.");
        }

        var name = ReadExactly(stream, 30, nameLength);
        if (!name.SequenceEqual(PngEntryName))
        {
            throw new InvalidDataException("icon.png is not the leading ZIP entry.");
        }

        var iconOffset = checked(30L + nameLength + extraLength);
        var icon = ReadExactly(stream, iconOffset, checked((int)uncompressedSize));
        if (Crc32(icon) != expectedCrc32)
        {
            throw new InvalidDataException("The public package icon CRC is invalid.");
        }

        return icon;
    }

    private static byte[] ReadExactly(IStream stream, long offset, int count)
    {
        if (offset < 0 || count < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(offset));
        }

        stream.Seek(offset, 0, IntPtr.Zero);
        var result = new byte[count];
        var buffer = new byte[Math.Min(128 * 1_024, Math.Max(1, count))];
        var bytesReadPointer = Marshal.AllocHGlobal(sizeof(int));
        try
        {
            var total = 0;
            while (total < count)
            {
                var requested = Math.Min(buffer.Length, count - total);
                Marshal.WriteInt32(bytesReadPointer, 0);
                stream.Read(buffer, requested, bytesReadPointer);
                var bytesRead = Marshal.ReadInt32(bytesReadPointer);
                if (bytesRead <= 0 || bytesRead > requested)
                {
                    throw new EndOfStreamException();
                }

                Buffer.BlockCopy(buffer, 0, result, total, bytesRead);
                total += bytesRead;
            }
        }
        finally
        {
            Marshal.FreeHGlobal(bytesReadPointer);
        }

        return result;
    }

    private static uint Crc32(ReadOnlySpan<byte> data)
    {
        var crc = uint.MaxValue;
        foreach (var value in data)
        {
            crc = Crc32Table[(crc ^ value) & 0xff] ^ (crc >> 8);
        }

        return crc ^ uint.MaxValue;
    }

    private static uint[] CreateCrc32Table()
    {
        var table = new uint[256];
        for (uint index = 0; index < table.Length; index++)
        {
            var value = index;
            for (var bit = 0; bit < 8; bit++)
            {
                value = (value & 1) == 0 ? value >> 1 : (value >> 1) ^ 0xedb8_8320U;
            }
            table[index] = value;
        }
        return table;
    }
}
