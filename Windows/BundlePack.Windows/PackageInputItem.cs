namespace BundlePack.Windows;

public sealed class PackageInputItem
{
    public PackageInputItem()
    {
    }

    public PackageInputItem(string name, string path)
    {
        Name = name;
        Path = path;
    }

    public string Name { get; set; } = string.Empty;
    public string Path { get; set; } = string.Empty;
}
