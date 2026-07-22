using BundlePack.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace BundlePack.Windows;

public sealed partial class CreatePage
{
    private CancellationTokenSource BeginOperation(string message)
    {
        var cancellation = new CancellationTokenSource();
        _operationCancellation = cancellation;
        BusyMessageText.Text = message;
        BusyProgressBar.Value = 0;
        BusyPercentText.Text = "0%";
        CancelOperationButton.IsEnabled = true;
        BusyOverlay.Visibility = Visibility.Visible;
        RootContent.IsHitTestVisible = false;
        RootContent.Opacity = 0.65;
        return cancellation;
    }

    private void EndOperation(CancellationTokenSource cancellation)
    {
        if (ReferenceEquals(_operationCancellation, cancellation))
        {
            _operationCancellation = null;
        }
        cancellation.Dispose();
        BusyOverlay.Visibility = Visibility.Collapsed;
        RootContent.IsHitTestVisible = true;
        RootContent.Opacity = 1;
    }

    private void UpdateProgress(BundlePackOperationProgress progress)
    {
        BusyMessageText.Text = progress.Message;
        BusyProgressBar.Value = progress.FractionCompleted * 100;
        BusyPercentText.Text = $"{progress.FractionCompleted:P0}";
    }

    private void CancelOperation_Click(object sender, RoutedEventArgs e)
    {
        if (_operationCancellation is null)
        {
            return;
        }

        CancelOperationButton.IsEnabled = false;
        BusyMessageText.Text = "Cancelling…";
        _operationCancellation.Cancel();
    }

    private async Task ShowErrorAsync(string message)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "BundlePack",
            Content = message,
            CloseButtonText = "OK"
        };
        await dialog.ShowAsync();
    }
}
