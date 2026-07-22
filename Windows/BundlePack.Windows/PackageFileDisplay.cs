namespace BundlePack.Windows;

public sealed class PackageFileDisplay
{
    public PackageFileDisplay()
    {
    }

    public PackageFileDisplay(string path, string displaySize)
    {
        Path = path;
        DisplaySize = displaySize;
    }

    public string Path { get; set; } = string.Empty;
    public string DisplaySize { get; set; } = string.Empty;
}
