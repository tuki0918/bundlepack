namespace BundlePack.Core;

public static class BundlePackAnimation
{
    public static bool IsGif(ReadOnlySpan<byte> data) =>
        data.Length >= 6
        && (data[..6].SequenceEqual("GIF87a"u8) || data[..6].SequenceEqual("GIF89a"u8));

    public static void ValidateGif(byte[] data)
    {
        if (data.Length > BundlePackConstants.MaximumMetadataSize || !IsGif(data))
        {
            ThrowInvalid();
        }

        var offset = 6;
        var canvasWidth = ReadUInt16(data, ref offset);
        var canvasHeight = ReadUInt16(data, ref offset);
        if (canvasWidth <= 0
            || canvasHeight <= 0
            || canvasWidth > BundlePackConstants.MaximumAnimationCanvasDimension
            || canvasHeight > BundlePackConstants.MaximumAnimationCanvasDimension)
        {
            ThrowInvalid();
        }

        var packed = ReadByte(data, ref offset);
        _ = ReadByte(data, ref offset);
        _ = ReadByte(data, ref offset);
        if ((packed & 0x80) != 0)
        {
            Skip(data, ref offset, 3 * (1 << ((packed & 0x07) + 1)));
        }

        var canvasPixels = checked(canvasWidth * canvasHeight);
        var frameCount = 0;
        while (offset < data.Length)
        {
            switch (ReadByte(data, ref offset))
            {
                case 0x21:
                {
                    var label = ReadByte(data, ref offset);
                    if (label == 0xf9)
                    {
                        if (ReadByte(data, ref offset) != 4)
                        {
                            ThrowInvalid();
                        }
                        Skip(data, ref offset, 4);
                        if (ReadByte(data, ref offset) != 0)
                        {
                            ThrowInvalid();
                        }
                    }
                    else
                    {
                        SkipSubBlocks(data, ref offset, requiresData: false);
                    }
                    break;
                }
                case 0x2c:
                {
                    var left = ReadUInt16(data, ref offset);
                    var top = ReadUInt16(data, ref offset);
                    var width = ReadUInt16(data, ref offset);
                    var height = ReadUInt16(data, ref offset);
                    if (width <= 0
                        || height <= 0
                        || left + width > canvasWidth
                        || top + height > canvasHeight)
                    {
                        ThrowInvalid();
                    }

                    var imagePacked = ReadByte(data, ref offset);
                    if ((imagePacked & 0x80) != 0)
                    {
                        Skip(data, ref offset, 3 * (1 << ((imagePacked & 0x07) + 1)));
                    }

                    var minimumCodeSize = ReadByte(data, ref offset);
                    if (minimumCodeSize is < 2 or > 8)
                    {
                        ThrowInvalid();
                    }
                    SkipSubBlocks(data, ref offset, requiresData: true);
                    frameCount++;
                    if (frameCount > BundlePackConstants.MaximumAnimationFrames
                        || checked(canvasPixels * frameCount) > BundlePackConstants.MaximumAnimationTotalPixels)
                    {
                        ThrowInvalid();
                    }
                    break;
                }
                case 0x3b:
                    if (offset != data.Length || frameCount < 2)
                    {
                        ThrowInvalid();
                    }
                    return;
                default:
                    ThrowInvalid();
                    break;
            }
        }

        ThrowInvalid();
    }

    private static int ReadByte(byte[] data, ref int offset)
    {
        if ((uint)offset >= (uint)data.Length)
        {
            ThrowInvalid();
        }
        return data[offset++];
    }

    private static int ReadUInt16(byte[] data, ref int offset)
    {
        var low = ReadByte(data, ref offset);
        var high = ReadByte(data, ref offset);
        return low | (high << 8);
    }

    private static void Skip(byte[] data, ref int offset, int count)
    {
        if (count < 0 || offset > data.Length - count)
        {
            ThrowInvalid();
        }
        offset += count;
    }

    private static void SkipSubBlocks(byte[] data, ref int offset, bool requiresData)
    {
        var total = 0;
        while (true)
        {
            var count = ReadByte(data, ref offset);
            if (count == 0)
            {
                if (requiresData && total == 0)
                {
                    ThrowInvalid();
                }
                return;
            }
            Skip(data, ref offset, count);
            total += count;
        }
    }

    private static void ThrowInvalid() =>
        throw new BundlePackException(
            BundlePackError.InvalidAnimation,
            "The package animation must be a valid animated GIF with 2–120 frames, a canvas no larger than 1024 × 1024, and a size of 16 MB or less.");
}
