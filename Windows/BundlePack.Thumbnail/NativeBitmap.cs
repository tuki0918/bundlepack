using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace BundlePack.Thumbnail;

internal static class NativeBitmap
{
    public static IntPtr CreateDibSection(Bitmap bitmap)
    {
        var bitmapInfo = new BitmapInfo
        {
            Header = new BitmapInfoHeader
            {
                Size = checked((uint)Marshal.SizeOf<BitmapInfoHeader>()),
                Width = bitmap.Width,
                Height = -bitmap.Height,
                Planes = 1,
                BitCount = 32,
                Compression = 0,
                SizeImage = checked((uint)(bitmap.Width * bitmap.Height * 4))
            }
        };

        var handle = CreateDIBSection(
            IntPtr.Zero,
            ref bitmapInfo,
            0,
            out var destination,
            IntPtr.Zero,
            0);
        if (handle == IntPtr.Zero || destination == IntPtr.Zero)
        {
            if (handle != IntPtr.Zero)
            {
                DeleteObject(handle);
            }
            throw new InvalidOperationException("A 32-bit DIB section could not be created.");
        }

        var rectangle = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        var source = bitmap.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        try
        {
            var rowLength = checked(bitmap.Width * 4);
            var row = new byte[rowLength];
            for (var y = 0; y < bitmap.Height; y++)
            {
                Marshal.Copy(IntPtr.Add(source.Scan0, checked(y * source.Stride)), row, 0, rowLength);
                Marshal.Copy(row, 0, IntPtr.Add(destination, checked(y * rowLength)), rowLength);
            }
        }
        catch
        {
            DeleteObject(handle);
            throw;
        }
        finally
        {
            bitmap.UnlockBits(source);
        }

        return handle;
    }

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateDIBSection(
        IntPtr deviceContext,
        ref BitmapInfo bitmapInfo,
        uint usage,
        out IntPtr bits,
        IntPtr section,
        uint offset);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr value);

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public BitmapInfoHeader Header;
        public uint Colors;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        public uint Size;
        public int Width;
        public int Height;
        public ushort Planes;
        public ushort BitCount;
        public uint Compression;
        public uint SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public uint ColorsUsed;
        public uint ColorsImportant;
    }
}
