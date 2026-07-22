using System.Security.Cryptography;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;

namespace BundlePack.Windows;

public sealed partial class PasswordGeneratorDialog : ContentDialog
{
    private const string Lowercase = "abcdefghijkmnopqrstuvwxyz";
    private const string Uppercase = "ABCDEFGHJKLMNPQRSTUVWXYZ";
    private const string Digits = "23456789";
    private const string Symbols = "!@#$%^&*()-_=+[]{};:,.?";

    public PasswordGeneratorDialog()
    {
        InitializeComponent();
        GeneratePassword();
    }

    public string SelectedPassword => GeneratedPasswordTextBox.Text;

    private void Settings_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (LettersCountText is null)
        {
            return;
        }

        NormalizeCounts();
        UpdateCounts();
    }

    private void Generate_Click(object sender, RoutedEventArgs e) => GeneratePassword();

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        var password = GeneratedPasswordTextBox.Text;
        var data = new DataPackage();
        data.SetText(password);
        _ = Clipboard.SetContentWithOptions(
            data,
            new ClipboardContentOptions
            {
                IsAllowedInHistory = false,
                IsRoamable = false
            });
        _ = ClearClipboardLaterAsync(password);
    }

    private void GeneratePassword()
    {
        NormalizeCounts();
        var total = (int)TotalLengthNumberBox.Value;
        var digitCount = (int)DigitsNumberBox.Value;
        var symbolCount = (int)SymbolsNumberBox.Value;
        var letterCount = total - digitCount - symbolCount;
        var characters = new List<char>(total)
        {
            Pick(Lowercase),
            Pick(Uppercase)
        };

        for (var index = 2; index < letterCount; index++)
        {
            characters.Add(Pick(Lowercase + Uppercase));
        }

        for (var index = 0; index < digitCount; index++)
        {
            characters.Add(Pick(Digits));
        }

        for (var index = 0; index < symbolCount; index++)
        {
            characters.Add(Pick(Symbols));
        }

        for (var index = characters.Count - 1; index > 0; index--)
        {
            var replacement = RandomNumberGenerator.GetInt32(index + 1);
            (characters[index], characters[replacement]) = (characters[replacement], characters[index]);
        }

        GeneratedPasswordTextBox.Text = new string(characters.ToArray());
        UpdateCounts();
    }

    private void NormalizeCounts()
    {
        var total = Math.Clamp((int)TotalLengthNumberBox.Value, 12, 128);
        var digits = Math.Clamp((int)DigitsNumberBox.Value, 0, total - 2);
        var symbols = Math.Clamp((int)SymbolsNumberBox.Value, 0, total - digits - 2);
        TotalLengthNumberBox.Value = total;
        DigitsNumberBox.Value = digits;
        SymbolsNumberBox.Value = symbols;
    }

    private void UpdateCounts()
    {
        var total = (int)TotalLengthNumberBox.Value;
        var letters = total - (int)DigitsNumberBox.Value - (int)SymbolsNumberBox.Value;
        LettersCountText.Text = letters.ToString(System.Globalization.CultureInfo.InvariantCulture);
        CharacterCountText.Text = $"{total} characters";
    }

    private static char Pick(string characters) => characters[RandomNumberGenerator.GetInt32(characters.Length)];

    private static async Task ClearClipboardLaterAsync(string copiedPassword)
    {
        await Task.Delay(TimeSpan.FromSeconds(60));
        try
        {
            var content = Clipboard.GetContent();
            if (content.Contains(StandardDataFormats.Text)
                && string.Equals(await content.GetTextAsync(), copiedPassword, StringComparison.Ordinal))
            {
                Clipboard.Clear();
            }
        }
        catch
        {
            // Another process may own the clipboard by the time the timer expires.
        }
    }
}
