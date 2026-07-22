using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using BundlePack.Thumbnail;

var options = ParseArguments(args);
if (!options.TryGetValue("fixtures", out var fixtureDirectories) || fixtureDirectories.Count == 0)
{
    throw new ArgumentException("Provide at least one --fixtures directory.");
}

var files = fixtureDirectories
    .Select(Path.GetFullPath)
    .SelectMany(directory => Directory.EnumerateFiles(directory, "*.bundlepack"))
    .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
    .ToArray();
if (files.Length == 0)
{
    throw new InvalidOperationException("No BundlePack thumbnail fixtures were found.");
}

foreach (var path in files)
{
    using var file = File.OpenRead(path);
    var provider = new BundlePackThumbnailProvider();
    var stream = new ManagedComStream(file);
    Require(provider.Initialize(stream, 2) != 0, "A writable thumbnail stream was accepted.");
    Require(provider.Initialize(stream, 0) == 0, "The thumbnail provider could not be initialized.");
    Require(provider.Initialize(stream, 0) != 0, "The thumbnail provider accepted a second initialization.");

    var result = provider.GetThumbnail(256, out var bitmap, out var alphaType);
    try
    {
        Require(result == 0, $"Thumbnail generation failed for {Path.GetFileName(path)}: 0x{result:x8}");
        Require(bitmap != IntPtr.Zero, "The thumbnail provider returned an empty bitmap handle.");
        Require(alphaType == ThumbnailAlphaType.Argb, "The thumbnail provider did not declare alpha support.");
        Require(NativeMethods.GetObjectW(bitmap, Marshal.SizeOf<NativeBitmapInfo>(), out var bitmapInfo) != 0, "The HBITMAP could not be inspected.");
        Require(bitmapInfo.Width == 256 && Math.Abs(bitmapInfo.Height) == 256, "The thumbnail has unexpected dimensions.");
        Require(bitmapInfo.BitsPixel == 32, "The thumbnail is not a 32-bit DIB section.");
        Require(
            stream.MaximumPosition < file.Length,
            $"The thumbnail provider read the complete package instead of only its public icon: {Path.GetFileName(path)}");
    }
    finally
    {
        if (bitmap != IntPtr.Zero)
        {
            NativeMethods.DeleteObject(bitmap);
        }
    }
}

using (var invalidData = new MemoryStream("not a BundlePack"u8.ToArray(), writable: false))
{
    var provider = new BundlePackThumbnailProvider();
    Require(provider.Initialize(new ManagedComStream(invalidData), 0) == 0, "The invalid-stream test could not initialize.");
    Require(
        provider.GetThumbnail(256, out var bitmap, out _) != 0 && bitmap == IntPtr.Zero,
        "Invalid package data produced a thumbnail.");
}

Console.WriteLine($"PASS: Windows Explorer thumbnail provider rendered {files.Length} encrypted and unencrypted fixtures");

static Dictionary<string, List<string>> ParseArguments(string[] arguments)
{
    var result = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
    for (var index = 0; index < arguments.Length; index++)
    {
        if (!arguments[index].StartsWith("--", StringComparison.Ordinal) || index + 1 >= arguments.Length)
        {
            throw new ArgumentException($"Invalid argument: {arguments[index]}");
        }

        var name = arguments[index][2..];
        if (!result.TryGetValue(name, out var values))
        {
            values = [];
            result[name] = values;
        }
        values.Add(arguments[++index]);
    }

    return result;
}

static void Require(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

[StructLayout(LayoutKind.Sequential)]
struct NativeBitmapInfo
{
    public int Type;
    public int Width;
    public int Height;
    public int WidthBytes;
    public ushort Planes;
    public ushort BitsPixel;
    public IntPtr Bits;
}

static class NativeMethods
{
    [DllImport("gdi32.dll", SetLastError = true)]
    internal static extern int GetObjectW(IntPtr value, int bufferSize, out NativeBitmapInfo bitmap);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DeleteObject(IntPtr value);
}

sealed class ManagedComStream(Stream stream) : IStream
{
    public long MaximumPosition { get; private set; }

    public void Read(byte[] buffer, int count, IntPtr bytesRead)
    {
        var read = stream.Read(buffer, 0, count);
        MaximumPosition = Math.Max(MaximumPosition, stream.Position);
        if (bytesRead != IntPtr.Zero)
        {
            Marshal.WriteInt32(bytesRead, read);
        }
    }

    public void Seek(long offset, int origin, IntPtr newPosition)
    {
        var position = stream.Seek(offset, (SeekOrigin)origin);
        if (newPosition != IntPtr.Zero)
        {
            Marshal.WriteInt64(newPosition, position);
        }
    }

    public void Stat(out STATSTG statistics, int flags)
    {
        statistics = new STATSTG
        {
            cbSize = stream.Length,
            type = 2
        };
    }

    public void Clone(out IStream clone) => throw AccessDenied();
    public void Commit(int flags) => throw AccessDenied();
    public void CopyTo(IStream destination, long count, IntPtr bytesRead, IntPtr bytesWritten) => throw AccessDenied();
    public void LockRegion(long offset, long count, int lockType) => throw AccessDenied();
    public void Revert() => throw AccessDenied();
    public void SetSize(long size) => throw AccessDenied();
    public void UnlockRegion(long offset, long count, int lockType) => throw AccessDenied();
    public void Write(byte[] buffer, int count, IntPtr bytesWritten) => throw AccessDenied();

    private static COMException AccessDenied() => new("The fixture stream is read-only.", unchecked((int)0x80030005));
}
