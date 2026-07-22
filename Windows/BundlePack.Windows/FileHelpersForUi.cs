namespace BundlePack.Windows;

internal static class FileHelpersForUi
{
    public static bool HasMinimumPasswordLength(string password) =>
        new System.Globalization.StringInfo(password.Normalize(System.Text.NormalizationForm.FormC)).LengthInTextElements >= 12;

    public static string SafeFileName(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            return "BundlePack";
        }

        var invalid = Path.GetInvalidFileNameChars().Concat(['/', '\\', ':']).ToHashSet();
        return new string(trimmed.Select(character => invalid.Contains(character) ? '-' : character).ToArray());
    }
}
