using Microsoft.UI.Xaml;

namespace BundlePack.Windows;

public partial class App : Application
{
    public App()
    {
        InitializeComponent();
    }

    internal static MainWindow? MainWindow { get; private set; }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        MainWindow = new MainWindow();
        MainWindow.Activate();

        var packagePath = Environment.GetCommandLineArgs()
            .Skip(1)
            .FirstOrDefault(path => string.Equals(
                Path.GetExtension(path),
                BundlePack.Core.BundlePackConstants.FileExtension,
                StringComparison.OrdinalIgnoreCase));
        if (packagePath is not null)
        {
            MainWindow.OpenPackage(packagePath);
        }
    }
}
