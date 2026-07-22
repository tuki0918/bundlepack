using System.Buffers.Binary;

namespace BundlePack.Core;

public static class BundlePackIcon
{
    private static readonly byte[] PngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

    public static void ValidatePng(ReadOnlySpan<byte> data)
    {
        if (data.Length < 24
            || data.Length > BundlePackConstants.MaximumMetadataSize
            || !data[..8].SequenceEqual(PngSignature)
            || !data.Slice(12, 4).SequenceEqual("IHDR"u8))
        {
            throw new BundlePackException(BundlePackError.InvalidIcon, "The package icon must be a valid PNG image.");
        }

        var width = BinaryPrimitives.ReadUInt32BigEndian(data.Slice(16, 4));
        var height = BinaryPrimitives.ReadUInt32BigEndian(data.Slice(20, 4));
        if (width != 1_024 || height != 1_024)
        {
            throw new BundlePackException(BundlePackError.InvalidIcon, "The package icon must be a 1024 × 1024 PNG image.");
        }
    }
}
