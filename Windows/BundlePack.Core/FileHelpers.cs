using System.Globalization;
using System.Text;

namespace BundlePack.Core;

internal static class FileHelpers
{
    internal static readonly StringComparer OutputPathComparer = StringComparer.OrdinalIgnoreCase;
    private static readonly HashSet<string> WindowsReservedNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    };

    public static string NormalizeOutputPath(string value) => value.Normalize(NormalizationForm.FormC);

    public static string NormalizePassword(string password) => password.Normalize(NormalizationForm.FormC);

    public static bool IsPortableFileName(string name)
    {
        if (string.IsNullOrEmpty(name)
            || name.EndsWith(' ')
            || name.EndsWith('.')
            || name.Any(character => character < 0x20 || "<>:\"/\\|?*".Contains(character)))
        {
            return false;
        }

        var stem = name.Split('.', 2)[0];
        return !WindowsReservedNames.Contains(stem);
    }

    public static bool HasMinimumPasswordLength(string password)
    {
        var normalized = NormalizePassword(password);
        return new StringInfo(normalized).LengthInTextElements >= BundlePackConstants.MinimumPasswordCharacters;
    }

    public static bool HasValidDisplayMetadata(
        string title,
        string packageVersion,
        string author,
        string summary) =>
        IsValidDisplayText(title, BundlePackConstants.MaximumTitleBytes, allowsEmpty: false)
        && IsValidDisplayText(packageVersion, BundlePackConstants.MaximumPackageVersionBytes)
        && IsValidDisplayText(author, BundlePackConstants.MaximumAuthorBytes)
        && IsValidDisplayText(summary, BundlePackConstants.MaximumSummaryBytes);

    private static bool IsValidDisplayText(string value, int maximumBytes, bool allowsEmpty = true) =>
        (allowsEmpty || !string.IsNullOrWhiteSpace(value))
        && Encoding.UTF8.GetByteCount(value) <= maximumBytes
        && !value.Any(char.IsControl);

    public static string SafeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars().Concat(['/','\\', ':']).ToHashSet();
        var cleaned = new string(value.Select(character => invalid.Contains(character) ? '-' : character).ToArray())
            .Trim()
            .TrimEnd(' ', '.');
        var stem = cleaned.Split('.', 2)[0];
        return string.IsNullOrWhiteSpace(cleaned)
            || cleaned is "." or ".."
            || WindowsReservedNames.Contains(stem)
            ? "BundlePack"
            : cleaned;
    }

    public static string UniqueDestinationDirectory(string parentDirectory, string title)
    {
        var basePath = Path.Combine(parentDirectory, SafeFileName(title));
        if (!Directory.Exists(basePath) && !File.Exists(basePath))
        {
            return basePath;
        }

        for (var index = 2; ; index++)
        {
            var candidate = $"{basePath} {index}";
            if (!Directory.Exists(candidate) && !File.Exists(candidate))
            {
                return candidate;
            }
        }
    }

    public static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // Best-effort cleanup for temporary files.
        }
    }

    public static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch
        {
            // Best-effort cleanup for temporary files.
        }
    }

    public static async Task ReadExactlyAsync(Stream stream, Memory<byte> buffer, CancellationToken cancellationToken)
    {
        var total = 0;
        while (total < buffer.Length)
        {
            var count = await stream.ReadAsync(buffer[total..], cancellationToken).ConfigureAwait(false);
            if (count == 0)
            {
                throw new EndOfStreamException();
            }

            total += count;
        }
    }
}
