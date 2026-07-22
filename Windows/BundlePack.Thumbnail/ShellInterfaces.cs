using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace BundlePack.Thumbnail;

[ComImport]
[Guid("B824B49D-22AC-4161-AC8A-9916E8FA3F7F")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IInitializeWithStream
{
    [PreserveSig]
    int Initialize([MarshalAs(UnmanagedType.Interface)] IStream stream, uint mode);
}

[ComImport]
[Guid("E357FCCD-A995-4576-B01F-234630154E96")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IThumbnailProvider
{
    [PreserveSig]
    int GetThumbnail(uint edgeLength, out IntPtr bitmap, out ThumbnailAlphaType alphaType);
}

public enum ThumbnailAlphaType
{
    Unknown = 0,
    Rgb = 1,
    Argb = 2
}
