using System.Collections.ObjectModel;
using BundlePack.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;

namespace BundlePack.Windows;

public sealed partial class CreatePage : UserControl
{
    private byte[]? _defaultIconPng;
    private byte[]? _selectedIconPng;
    private CancellationTokenSource? _operationCancellation;

    public CreatePage()
    {
        InitializeComponent();
        PasswordBox.PlaceholderText =
            $"At least {BundlePackConstants.MinimumPasswordCharacters} characters";
        RootContent.AddHandler(
            UIElement.PointerWheelChangedEvent,
            new PointerEventHandler(RootContent_PointerWheelChanged),
            handledEventsToo: true);
        Loaded += CreatePage_Loaded;
    }

    public ObservableCollection<PackageInputItem> InputItems { get; } = [];

    private async void CreatePage_Loaded(object sender, RoutedEventArgs e)
    {
        if (_defaultIconPng is not null)
        {
            return;
        }

        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "DefaultPackageIcon.png");
            _defaultIconPng = await File.ReadAllBytesAsync(path);
            await ImageHelpers.SetPngAsync(IconPreview, _defaultIconPng);
            UpdateProtectionState();
        }
        catch (Exception exception)
        {
            await ShowErrorAsync(exception.Message);
        }
    }

    private async void ChooseIcon_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.PicturesLibrary,
            ViewMode = PickerViewMode.Thumbnail
        };
        foreach (var extension in new[] { ".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff" })
        {
            picker.FileTypeFilter.Add(extension);
        }
        PickerHelpers.Initialize(picker);
        var file = await picker.PickSingleFileAsync();
        if (file is not null)
        {
            await SetCustomIconAsync(file.Path);
        }
    }

    private async void Icon_Drop(object sender, DragEventArgs e)
    {
        e.Handled = true;
        SetIconDropHighlight(isVisible: false);
        if (!e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            return;
        }

        var items = await e.DataView.GetStorageItemsAsync();
        if (items.Count == 1 && items[0] is StorageFile file
            && ImageHelpers.IsSupportedPackageIconPath(file.Path))
        {
            await SetCustomIconAsync(file.Path);
            return;
        }

        await ShowErrorAsync("Drop one PNG, JPEG, BMP, or TIFF image to use it as the package icon.");
    }

    private void Icon_DragEnter(object sender, DragEventArgs e)
    {
        e.Handled = true;
        SetIconDropHighlight(e.DataView.Contains(StandardDataFormats.StorageItems));
    }

    private void Icon_DragLeave(object sender, DragEventArgs e)
    {
        e.Handled = true;
        SetIconDropHighlight(isVisible: false);
    }

    private void Icon_DragOver(object sender, DragEventArgs e)
    {
        e.Handled = true;
        if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            SetIconDropHighlight(isVisible: true);
            e.AcceptedOperation = DataPackageOperation.Copy;
            e.DragUIOverride.Caption = "Use as package icon";
            return;
        }

        SetIconDropHighlight(isVisible: false);
    }

    private void SetIconDropHighlight(bool isVisible) =>
        IconDropHighlight.Visibility = isVisible ? Visibility.Visible : Visibility.Collapsed;

    private async Task SetCustomIconAsync(string path)
    {
        try
        {
            var data = await ImageHelpers.NormalizePackageIconAsync(path);
            BundlePackIcon.ValidatePng(data);
            _selectedIconPng = data;
            await ImageHelpers.SetPngAsync(IconPreview, data);
            RemoveIconButton.Visibility = Visibility.Visible;
        }
        catch (Exception exception)
        {
            await ShowErrorAsync(exception.Message);
        }
    }

    private async void RemoveIcon_Click(object sender, RoutedEventArgs e)
    {
        _selectedIconPng = null;
        RemoveIconButton.Visibility = Visibility.Collapsed;
        if (_defaultIconPng is not null)
        {
            await ImageHelpers.SetPngAsync(IconPreview, _defaultIconPng);
        }
    }

    private async void AddFiles_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
            ViewMode = PickerViewMode.List
        };
        picker.FileTypeFilter.Add("*");
        PickerHelpers.Initialize(picker);
        var files = await picker.PickMultipleFilesAsync();
        AddInputs(files.Select(file => file.Path));
    }

    private async void AddFolder_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
            ViewMode = PickerViewMode.List
        };
        picker.FileTypeFilter.Add("*");
        PickerHelpers.Initialize(picker);
        var folder = await picker.PickSingleFolderAsync();
        if (folder is not null)
        {
            AddInputs([folder.Path]);
        }
    }

    private void IncludedFiles_DragEnter(object sender, DragEventArgs e)
    {
        e.Handled = true;
        SetIncludedFilesDropHighlight(e.DataView.Contains(StandardDataFormats.StorageItems));
    }

    private void IncludedFiles_DragLeave(object sender, DragEventArgs e)
    {
        e.Handled = true;
        SetIncludedFilesDropHighlight(isVisible: false);
    }

    private void IncludedFiles_DragOver(object sender, DragEventArgs e)
    {
        e.Handled = true;
        if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            SetIncludedFilesDropHighlight(isVisible: true);
            e.AcceptedOperation = DataPackageOperation.Copy;
            e.DragUIOverride.Caption = "Add to this BundlePack";
            return;
        }

        SetIncludedFilesDropHighlight(isVisible: false);
    }

    private async void IncludedFiles_Drop(object sender, DragEventArgs e)
    {
        e.Handled = true;
        SetIncludedFilesDropHighlight(isVisible: false);
        if (!e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            return;
        }

        var items = await e.DataView.GetStorageItemsAsync();
        AddInputs(items.Select(item => item.Path));
    }

    private void SetIncludedFilesDropHighlight(bool isVisible) =>
        IncludedFilesDropHighlight.Visibility = isVisible ? Visibility.Visible : Visibility.Collapsed;

    private void RootContent_PointerWheelChanged(object sender, PointerRoutedEventArgs e)
    {
        var pointerProperties = e.GetCurrentPoint(RootContent).Properties;
        if (pointerProperties.IsHorizontalMouseWheel || pointerProperties.MouseWheelDelta == 0)
        {
            return;
        }

        e.Handled = ScrollByMouseWheel(pointerProperties.MouseWheelDelta);
    }

    internal bool ScrollByMouseWheel(int wheelDelta)
    {
        if (BusyOverlay.Visibility == Visibility.Visible)
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

    private void AddInputs(IEnumerable<string> paths)
    {
        var existing = InputItems.Select(item => item.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var path in paths)
        {
            var fullPath = Path.GetFullPath(path);
            if (existing.Add(fullPath))
            {
                InputItems.Add(new PackageInputItem(Path.GetFileName(fullPath.TrimEnd('\\', '/')), fullPath));
            }
        }

        UpdateInputState();
    }

    private void RemoveInput_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string path })
        {
            return;
        }

        var item = InputItems.FirstOrDefault(candidate => string.Equals(candidate.Path, path, StringComparison.OrdinalIgnoreCase));
        if (item is not null)
        {
            InputItems.Remove(item);
            UpdateInputState();
        }
    }

    private void UpdateInputState()
    {
        var hasItems = InputItems.Count > 0;
        EmptyFilesPanel.Visibility = hasItems ? Visibility.Collapsed : Visibility.Visible;
        InputList.Visibility = hasItems ? Visibility.Visible : Visibility.Collapsed;
    }

    private void Protection_Checked(object sender, RoutedEventArgs e) => UpdateProtectionState();

    private void UpdateProtectionState()
    {
        var encrypted = EncryptedRadio.IsChecked == true;
        if (PasswordPanel is not null)
        {
            PasswordPanel.Visibility = encrypted ? Visibility.Visible : Visibility.Collapsed;
        }
        if (PasswordReminderText is not null)
        {
            PasswordReminderText.Visibility = encrypted ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private async void GeneratePassword_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new PasswordGeneratorDialog { XamlRoot = XamlRoot };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            PasswordBox.Password = dialog.SelectedPassword;
            ConfirmPasswordBox.Password = dialog.SelectedPassword;
        }
    }

    private async void Create_Click(object sender, RoutedEventArgs e)
    {
        if (_defaultIconPng is null)
        {
            await ShowErrorAsync("The default package icon is unavailable.");
            return;
        }

        if (InputItems.Count == 0)
        {
            await ShowErrorAsync("Choose at least one file or folder to include.");
            return;
        }

        var encrypted = EncryptedRadio.IsChecked == true;
        if (encrypted && !string.Equals(PasswordBox.Password, ConfirmPasswordBox.Password, StringComparison.Ordinal))
        {
            await ShowErrorAsync("Password and Confirm do not match.");
            return;
        }

        if (encrypted && !FileHelpersForUi.HasMinimumPasswordLength(PasswordBox.Password))
        {
            await ShowErrorAsync(
                $"The password must contain at least {BundlePackConstants.MinimumPasswordCharacters} characters.");
            return;
        }

        var picker = new FileSavePicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
            SuggestedFileName = FileHelpersForUi.SafeFileName(NameTextBox.Text)
        };
        picker.FileTypeChoices.Add("BundlePack archive", [BundlePackConstants.FileExtension]);
        PickerHelpers.Initialize(picker);
        var destination = await picker.PickSaveFileAsync();
        if (destination is null)
        {
            return;
        }

        var cancellation = BeginOperation("Preparing files…");
        var progress = new Progress<BundlePackOperationProgress>(UpdateProgress);
        try
        {
            using var created = await BundlePackService.CreateAsync(new PackageCreationRequest(
                NameTextBox.Text,
                VersionTextBox.Text,
                AuthorTextBox.Text,
                DescriptionTextBox.Text,
                InputItems.Select(item => item.Path).ToArray(),
                _selectedIconPng ?? _defaultIconPng,
                encrypted,
                encrypted ? PasswordBox.Password : string.Empty,
                destination.Path),
                cancellation.Token,
                progress);
            PasswordBox.Password = string.Empty;
            ConfirmPasswordBox.Password = string.Empty;
            StatusInfoBar.Severity = InfoBarSeverity.Success;
            StatusInfoBar.Title = "BundlePack created";
            StatusInfoBar.Message = destination.Path;
            StatusInfoBar.IsOpen = true;
        }
        catch (OperationCanceledException)
        {
            StatusInfoBar.Severity = InfoBarSeverity.Informational;
            StatusInfoBar.Title = "Creation cancelled";
            StatusInfoBar.Message = "Temporary package files were removed.";
            StatusInfoBar.IsOpen = true;
        }
        catch (Exception exception)
        {
            await ShowErrorAsync(exception.Message);
        }
        finally
        {
            EndOperation(cancellation);
        }
    }

}
