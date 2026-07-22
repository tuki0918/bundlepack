namespace BundlePack.Windows;

internal static class PickerHelpers
{
    public static void Initialize(object picker)
    {
        var window = App.MainWindow ?? throw new InvalidOperationException("The main window is not available.");
        var handle = WinRT.Interop.WindowNative.GetWindowHandle(window);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, handle);
    }
}
