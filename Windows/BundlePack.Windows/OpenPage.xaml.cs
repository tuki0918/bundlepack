using System.Collections.ObjectModel;
using BundlePack.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.System;

namespace BundlePack.Windows;

public sealed partial class OpenPage : UserControl, IDisposable
{
    private OpenedBundlePack? _openedPackage;
    private CancellationTokenSource? _operationCancellation;

    public OpenPage()
    {
        InitializeComponent();
        PackageContent.AddHandler(
            UIElement.PointerWheelChangedEvent,
            new PointerEventHandler(PackageContent_PointerWheelChanged),
            handledEventsToo: true);
    }

    public ObservableCollection<PackageFileDisplay> Contents { get; } = [];

    internal async Task LoadPackageAsync(string path)
    {
        if (_operationCancellation is not null)
        {
            return;
        }
        var cancellation = BeginOperation("Reading package…");
        var progress = new Progress<BundlePackOperationProgress>(UpdateProgress);
        try
        {
            var package = await BundlePackService.OpenAsync(
                path,
                cancellationToken: cancellation.Token,
                progress: progress);
            ReplaceOpenedPackage(package);
            await DisplayPackageAsync(package);
        }
        catch (OperationCanceledException)
        {
            ShowStatus(InfoBarSeverity.Informational, "Opening cancelled", "The previous package remains unchanged.");
        }
        catch (Exception exception)
        {
            ShowStatus(InfoBarSeverity.Error, "Could not open BundlePack", exception.Message);
        }
        finally
        {
            EndOperation(cancellation);
        }
    }

    private async void ChoosePackage_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
            ViewMode = PickerViewMode.List
        };
        picker.FileTypeFilter.Add(BundlePackConstants.FileExtension);
        PickerHelpers.Initialize(picker);
        var file = await picker.PickSingleFileAsync();
        if (file is not null)
        {
            await LoadPackageAsync(file.Path);
        }
    }

    private void RootGrid_DragOver(object sender, DragEventArgs e)
    {
        if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            e.AcceptedOperation = DataPackageOperation.Copy;
            e.DragUIOverride.Caption = "Open BundlePack";
        }
    }

    private async void RootGrid_Drop(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            return;
        }

        var items = await e.DataView.GetStorageItemsAsync();
        var file = items.OfType<StorageFile>().FirstOrDefault(candidate => string.Equals(
            candidate.FileType,
            BundlePackConstants.FileExtension,
            StringComparison.OrdinalIgnoreCase));
        if (file is not null)
        {
            await LoadPackageAsync(file.Path);
        }
    }

    private void PackageContent_PointerWheelChanged(object sender, PointerRoutedEventArgs e)
    {
        var pointerProperties = e.GetCurrentPoint(PackageContent).Properties;
        if (pointerProperties.IsHorizontalMouseWheel || pointerProperties.MouseWheelDelta == 0)
        {
            return;
        }

        e.Handled = ScrollByMouseWheel(pointerProperties.MouseWheelDelta);
    }

    internal bool ScrollByMouseWheel(int wheelDelta)
    {
        if (BusyOverlay.Visibility == Visibility.Visible || PackageContent.Visibility != Visibility.Visible)
        {
            return false;
        }

        var targetOffset = Math.Clamp(
            PageScrollViewer.VerticalOffset - wheelDelta,
            0,
            PageScrollViewer.ScrollableHeight);
        PageScrollViewer.ChangeView(null, targetOffset, null, true);
        return true;
    }

    private async void Unlock_Click(object sender, RoutedEventArgs e) => await UnlockAsync();

    private async void UnlockPassword_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter)
        {
            e.Handled = true;
            await UnlockAsync();
        }
    }

    private async Task UnlockAsync()
    {
        if (_openedPackage is null || !_openedPackage.IsEncrypted)
        {
            return;
        }

        if (!FileHelpersForUi.HasMinimumPasswordLength(UnlockPasswordBox.Password))
        {
            ShowStatus(InfoBarSeverity.Warning, "Password required", "Enter a password containing at least 12 characters.");
            return;
        }

        var cancellation = BeginOperation("Decrypting package…");
        var progress = new Progress<BundlePackOperationProgress>(UpdateProgress);
        try
        {
            var unlocked = await BundlePackService.OpenAsync(
                _openedPackage.SourcePath,
                UnlockPasswordBox.Password,
                cancellation.Token,
                progress);
            ReplaceOpenedPackage(unlocked);
            UnlockPasswordBox.Password = string.Empty;
            await DisplayPackageAsync(unlocked);
            ShowStatus(InfoBarSeverity.Success, "Decrypted and validated", "The package is ready to extract.");
        }
        catch (OperationCanceledException)
        {
            ShowStatus(InfoBarSeverity.Informational, "Unlock cancelled", "The package remains locked.");
        }
        catch (Exception exception)
        {
            ShowStatus(InfoBarSeverity.Error, "Package remains locked", exception.Message);
        }
        finally
        {
            EndOperation(cancellation);
        }
    }

    private async void Extract_Click(object sender, RoutedEventArgs e)
    {
        if (_openedPackage?.Archive is null)
        {
            return;
        }

        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
            ViewMode = PickerViewMode.List
        };
        picker.FileTypeFilter.Add("*");
        PickerHelpers.Initialize(picker);
        var folder = await picker.PickSingleFolderAsync();
        if (folder is null)
        {
            return;
        }

        var cancellation = BeginOperation("Preparing extraction…");
        var progress = new Progress<BundlePackOperationProgress>(UpdateProgress);
        try
        {
            var destination = await BundlePackService.ExtractAsync(
                _openedPackage,
                folder.Path,
                cancellation.Token,
                progress);
            ShowStatus(InfoBarSeverity.Success, "Extracted safely", destination);
            _ = await Launcher.LaunchFolderPathAsync(destination);
        }
        catch (OperationCanceledException)
        {
            ShowStatus(InfoBarSeverity.Informational, "Extraction cancelled", "No incomplete extraction folder was kept.");
        }
        catch (Exception exception)
        {
            ShowStatus(InfoBarSeverity.Error, "Extraction failed", exception.Message);
        }
        finally
        {
            EndOperation(cancellation);
        }
    }

    private async Task DisplayPackageAsync(OpenedBundlePack package)
    {
        InitialPanel.Visibility = Visibility.Collapsed;
        PackageContent.Visibility = Visibility.Visible;
        await ImageHelpers.SetPngAsync(PackageIcon, package.IconPng);

        Contents.Clear();
        if (package.Archive is null)
        {
            PackageTitleText.Text = "Encrypted BundlePack";
            MetadataBadges.Visibility = Visibility.Collapsed;
            AuthorText.Visibility = Visibility.Collapsed;
            SummaryText.Visibility = Visibility.Collapsed;
            LockedDescriptionText.Visibility = Visibility.Visible;
            UnlockPanel.Visibility = Visibility.Visible;
            DetailsPanel.Visibility = Visibility.Collapsed;
            ExtractButton.Visibility = Visibility.Collapsed;
            ShowStatus(
                InfoBarSeverity.Informational,
                "Encrypted package",
                $"Original archive size: {FormatBytes(package.OriginalArchiveSize)}");
            return;
        }

        var archive = package.Archive;
        PackageTitleText.Text = archive.Manifest.Title;
        VersionText.Text = $"v{archive.Manifest.PackageVersion}";
        FileCountText.Text = $"{archive.PayloadFiles.Count} files";
        SizeText.Text = FormatBytes(archive.ArchiveSize);
        AuthorText.Text = archive.Manifest.Author;
        SummaryText.Text = archive.Manifest.Summary;
        MetadataBadges.Visibility = Visibility.Visible;
        AuthorText.Visibility = string.IsNullOrWhiteSpace(archive.Manifest.Author) ? Visibility.Collapsed : Visibility.Visible;
        SummaryText.Visibility = string.IsNullOrWhiteSpace(archive.Manifest.Summary) ? Visibility.Collapsed : Visibility.Visible;
        LockedDescriptionText.Visibility = Visibility.Collapsed;
        UnlockPanel.Visibility = Visibility.Collapsed;
        DetailsPanel.Visibility = Visibility.Visible;
        ExtractButton.Visibility = Visibility.Visible;
        ExpandedSizeText.Text = $"Expanded: {FormatBytes(archive.ExpandedSize)}";
        foreach (var file in archive.PayloadFiles)
        {
            Contents.Add(new PackageFileDisplay(file.Path, FormatBytes(file.Size)));
        }

        ShowStatus(
            package.IsEncrypted ? InfoBarSeverity.Success : InfoBarSeverity.Warning,
            package.IsEncrypted ? "Decrypted and validated" : "Unencrypted ZIP-compatible package",
            package.IsEncrypted ? "Paths validated." : "File names and contents are not encrypted.");
    }

    private void ReplaceOpenedPackage(OpenedBundlePack package)
    {
        DisposeOpenedPackage();
        _openedPackage = package;
    }

    private void DisposeOpenedPackage()
    {
        _openedPackage?.Dispose();
        _openedPackage = null;
    }

    public void Dispose()
    {
        _operationCancellation?.Cancel();
        _operationCancellation?.Dispose();
        _operationCancellation = null;
        DisposeOpenedPackage();
        GC.SuppressFinalize(this);
    }

}
