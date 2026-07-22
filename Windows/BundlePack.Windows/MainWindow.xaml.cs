using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;

namespace BundlePack.Windows;

public sealed partial class MainWindow : Window
{
    private readonly CreatePage _createPage = new();
    private readonly OpenPage _openPage = new();

    public MainWindow()
    {
        InitializeComponent();
        Title = "BundlePack";
        AppWindow.Resize(new global::Windows.Graphics.SizeInt32(1_100, 820));
        Closed += (_, _) => _openPage.Dispose();
        ShowPage(_createPage, createSelected: true);
    }

    public void OpenPackage(string path)
    {
        ShowPage(_openPage, createSelected: false);
        _ = _openPage.LoadPackageAsync(path);
    }

    private void CreateNavigationButton_Click(object sender, RoutedEventArgs e)
    {
        ShowPage(_createPage, createSelected: true);
    }

    private void OpenNavigationButton_Click(object sender, RoutedEventArgs e)
    {
        ShowPage(_openPage, createSelected: false);
    }

    private void ShowPage(UIElement page, bool createSelected)
    {
        CreateNavigationButton.IsChecked = createSelected;
        OpenNavigationButton.IsChecked = !createSelected;

        if (PageHost.Children.Count == 1 && ReferenceEquals(PageHost.Children[0], page))
        {
            return;
        }

        PageHost.Children.Clear();
        PageHost.Children.Add(page);
    }
}
