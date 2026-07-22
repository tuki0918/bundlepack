using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace BundlePack.Thumbnail;

[ComVisible(true)]
[Guid(ClassId)]
[ClassInterface(ClassInterfaceType.None)]
public sealed class BundlePackThumbnailProvider : IInitializeWithStream, IThumbnailProvider
{
    public const string ClassId = "645A25AB-1F31-4147-A47B-46E8515BF79D";

    private const int Success = 0;
    private const int AccessDenied = unchecked((int)0x80030005);
    private const int AlreadyInitialized = unchecked((int)0x800704DF);
    private const int InvalidArgument = unchecked((int)0x80070057);
    private IStream? _stream;

    public int Initialize(IStream stream, uint mode)
    {
        if (_stream is not null)
        {
            return AlreadyInitialized;
        }
        if (stream is null)
        {
            return InvalidArgument;
        }
        if ((mode & 0x0000_0003U) != 0)
        {
            return AccessDenied;
        }

        _stream = stream;
        return Success;
    }

    public int GetThumbnail(uint edgeLength, out IntPtr bitmap, out ThumbnailAlphaType alphaType)
    {
        bitmap = IntPtr.Zero;
        alphaType = ThumbnailAlphaType.Unknown;
        if (_stream is null || edgeLength == 0)
        {
            return InvalidArgument;
        }

        try
        {
            var iconPng = PublicIconReader.Read(_stream);
            using var sourceStream = new MemoryStream(iconPng, writable: false);
            using var source = Image.FromStream(sourceStream, useEmbeddedColorManagement: true, validateImageData: true);
            var size = checked((int)Math.Min(edgeLength, 1_024U));
            using var thumbnail = new Bitmap(size, size, PixelFormat.Format32bppPArgb);
            using (var graphics = Graphics.FromImage(thumbnail))
            {
                graphics.CompositingMode = CompositingMode.SourceCopy;
                graphics.CompositingQuality = CompositingQuality.HighQuality;
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                graphics.SmoothingMode = SmoothingMode.HighQuality;
                graphics.Clear(Color.Transparent);
                graphics.DrawImage(source, new Rectangle(0, 0, size, size));
            }

            bitmap = NativeBitmap.CreateDibSection(thumbnail);
            alphaType = ThumbnailAlphaType.Argb;
            return Success;
        }
        catch (Exception exception)
        {
            return Marshal.GetHRForException(exception);
        }
    }
}
