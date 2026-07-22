using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace BundlePack.Windows;

internal static class ImageHelpers
{
    private const uint PackageIconSize = 1_024;
    private const long MaximumSourceBytes = 32L * 1_024 * 1_024;
    private const uint MaximumSourceDimension = 16_384;
    private const ulong MaximumSourcePixels = 100_000_000;
    private static readonly HashSet<string> SupportedPackageIconExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"
    };

    public static bool IsSupportedPackageIconPath(string path) =>
        SupportedPackageIconExtensions.Contains(Path.GetExtension(path));

    public static async Task<byte[]> NormalizePackageIconAsync(string path)
    {
        var fullPath = Path.GetFullPath(path);
        var sourceLength = new FileInfo(fullPath).Length;
        if (sourceLength <= 0 || sourceLength > MaximumSourceBytes)
        {
            throw new InvalidDataException("The selected image must be 32 MB or smaller.");
        }

        var file = await StorageFile.GetFileFromPathAsync(fullPath);
        using var input = await file.OpenReadAsync();
        var decoder = await BitmapDecoder.CreateAsync(input);
        if (decoder.PixelWidth == 0
            || decoder.PixelHeight == 0
            || decoder.OrientedPixelWidth == 0
            || decoder.OrientedPixelHeight == 0
            || decoder.PixelWidth > MaximumSourceDimension
            || decoder.PixelHeight > MaximumSourceDimension
            || decoder.OrientedPixelWidth > MaximumSourceDimension
            || decoder.OrientedPixelHeight > MaximumSourceDimension
            || checked((ulong)decoder.PixelWidth * decoder.PixelHeight) > MaximumSourcePixels)
        {
            throw new InvalidDataException("The selected image dimensions exceed the safety limit.");
        }

        var scale = Math.Min(
            (double)PackageIconSize / decoder.OrientedPixelWidth,
            (double)PackageIconSize / decoder.OrientedPixelHeight);
        var scaledWidth = Math.Max(1U, checked((uint)Math.Round(decoder.PixelWidth * scale)));
        var scaledHeight = Math.Max(1U, checked((uint)Math.Round(decoder.PixelHeight * scale)));
        var orientedWidth = Math.Min(
            PackageIconSize,
            Math.Max(1U, checked((uint)Math.Round(decoder.OrientedPixelWidth * scale))));
        var orientedHeight = Math.Min(
            PackageIconSize,
            Math.Max(1U, checked((uint)Math.Round(decoder.OrientedPixelHeight * scale))));
        var transform = new BitmapTransform
        {
            ScaledWidth = scaledWidth,
            ScaledHeight = scaledHeight,
            InterpolationMode = BitmapInterpolationMode.Fant
        };
        var provider = await decoder.GetPixelDataAsync(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied,
            transform,
            ExifOrientationMode.RespectExifOrientation,
            ColorManagementMode.ColorManageToSRgb);
        var sourcePixels = provider.DetachPixelData();
        var outputPixels = new byte[checked((int)(PackageIconSize * PackageIconSize * 4))];
        var expectedSourceLength = checked((int)(orientedWidth * orientedHeight * 4));
        if (sourcePixels.Length != expectedSourceLength)
        {
            throw new InvalidDataException("The selected image could not be oriented correctly.");
        }

        var x = checked((int)((PackageIconSize - orientedWidth) / 2));
        var y = checked((int)((PackageIconSize - orientedHeight) / 2));
        var sourceStride = checked((int)(orientedWidth * 4));
        var outputStride = checked((int)(PackageIconSize * 4));
        for (var row = 0; row < orientedHeight; row++)
        {
            System.Buffer.BlockCopy(
                sourcePixels,
                checked((int)row * sourceStride),
                outputPixels,
                checked((y + (int)row) * outputStride + x * 4),
                sourceStride);
        }

        using var output = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, output);
        encoder.SetPixelData(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied,
            PackageIconSize,
            PackageIconSize,
            double.IsFinite(decoder.DpiX) && decoder.DpiX > 0 ? decoder.DpiX : 96,
            double.IsFinite(decoder.DpiY) && decoder.DpiY > 0 ? decoder.DpiY : 96,
            outputPixels);
        await encoder.FlushAsync();

        var result = new byte[checked((int)output.Size)];
        using var reader = new DataReader(output.GetInputStreamAt(0));
        await reader.LoadAsync(checked((uint)output.Size));
        reader.ReadBytes(result);
        return result;
    }

    public static async Task SetPngAsync(Image image, byte[] data)
    {
        using var stream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(stream))
        {
            writer.WriteBytes(data);
            await writer.StoreAsync();
            await writer.FlushAsync();
            writer.DetachStream();
        }

        stream.Seek(0);
        var bitmap = new BitmapImage();
        await bitmap.SetSourceAsync(stream);
        image.Source = bitmap;
    }
}
