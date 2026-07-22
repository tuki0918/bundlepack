using BundlePack.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace BundlePack.Windows;

public sealed partial class OpenPage
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

    private void ShowStatus(InfoBarSeverity severity, string title, string message)
    {
        StatusInfoBar.Severity = severity;
        StatusInfoBar.Title = title;
        StatusInfoBar.Message = message;
        StatusInfoBar.IsOpen = true;
    }

    private static string FormatBytes(ulong bytes)
    {
        string[] units = ["bytes", "KB", "MB", "GB", "TB"];
        var value = (double)bytes;
        var unit = 0;
        while (value >= 1_024 && unit < units.Length - 1)
        {
            value /= 1_024;
            unit++;
        }

        return unit == 0 ? $"{bytes} {units[unit]}" : $"{value:0.#} {units[unit]}";
    }
}
