using System.IO.Compression;
using System.Text;
using System.Text.Json;
using BundlePack.Core;

internal static class TestSupport
{
    public static async Task VerifyMacFixturesAsync(
        string fixturesDirectory,
        string fixturePassword,
        string unicodeFixturePassword)
    {
        var unencryptedPath = Path.Combine(fixturesDirectory, "macos-unencrypted.bundlepack");
        var encryptedPath = Path.Combine(fixturesDirectory, "macos-encrypted.bundlepack");
        var unicodePasswordPath = Path.Combine(fixturesDirectory, "macos-unicode-password.bundlepack");
        Require(File.Exists(unencryptedPath), $"The macOS fixture is missing: {unencryptedPath}");
        Require(File.Exists(encryptedPath), $"The macOS fixture is missing: {encryptedPath}");
        Require(File.Exists(unicodePasswordPath), $"The macOS fixture is missing: {unicodePasswordPath}");

        using var unencrypted = await BundlePackService.OpenAsync(unencryptedPath);
        var unencryptedArchive = unencrypted.Archive
            ?? throw new InvalidOperationException("The macOS unencrypted fixture did not open on Windows.");
        VerifyPayload(unencryptedArchive);

        using var encrypted = await BundlePackService.OpenAsync(encryptedPath, fixturePassword);
        var encryptedArchive = encrypted.Archive
            ?? throw new InvalidOperationException("The macOS encrypted fixture did not open on Windows.");
        VerifyPayload(encryptedArchive);

        using var unicodePassword = await BundlePackService.OpenAsync(unicodePasswordPath, unicodeFixturePassword);
        var unicodePasswordArchive = unicodePassword.Archive
            ?? throw new InvalidOperationException("The macOS Unicode-password fixture did not open on Windows.");
        VerifyPayload(unicodePasswordArchive);
    }

    public static void VerifyPayload(BundlePackArchiveInfo archive)
    {
        Require(
            archive.PayloadFiles.Any(file => file.Path == "hello.txt"),
            "The compatibility text file is missing.");
        Require(
            archive.PayloadFiles.Any(file => file.Path == "nested/data.bin"),
            "The compatibility nested file is missing.");
    }

    public static void CreateUnsafeNameArchive(string path, byte[] iconPng)
    {
        CreateTestArchive(path, iconPng, "[]", "payload/CON.txt", "unsafe"u8.ToArray());
    }

    public static void CreateTestArchive(
        string path,
        byte[] iconPng,
        string manifestFilesJson,
        string payloadPath,
        byte[] payload,
        string title = "Test",
        string? extraRootEntryPath = null)
    {
        using var stream = File.Create(path);
        using var archive = new ZipArchive(stream, ZipArchiveMode.Create);
        WriteEntry(archive, "icon.png", iconPng, CompressionLevel.NoCompression);
        var manifest = $"{{\"format\":\"com.tuki0918.bundlepack\",\"formatVersion\":1,\"title\":{JsonSerializer.Serialize(title)},\"packageVersion\":\"1\",\"author\":\"\",\"summary\":\"\",\"createdAt\":\"2026-07-21T00:00:00Z\",\"files\":{manifestFilesJson}}}";
        WriteEntry(archive, "manifest.json", Encoding.UTF8.GetBytes(manifest), CompressionLevel.NoCompression);
        WriteEntry(archive, payloadPath, payload, CompressionLevel.NoCompression);
        if (extraRootEntryPath is not null)
        {
            WriteEntry(archive, extraRootEntryPath, "unexpected"u8.ToArray(), CompressionLevel.NoCompression);
        }
    }

    public static void TamperStoredPayload(
        string path,
        ReadOnlySpan<byte> original,
        ReadOnlySpan<byte> replacement)
    {
        if (original.Length == 0 || original.Length != replacement.Length)
        {
            throw new ArgumentException("Tamper values must have the same non-zero length.");
        }

        var data = File.ReadAllBytes(path);
        var offset = data.AsSpan().IndexOf(original);
        if (offset < 0)
        {
            throw new InvalidOperationException("The stored payload could not be located.");
        }

        replacement.CopyTo(data.AsSpan(offset, replacement.Length));
        File.WriteAllBytes(path, data);
    }

    public static Dictionary<string, string> ParseArguments(string[] arguments)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (var index = 0; index < arguments.Length; index++)
        {
            if (!arguments[index].StartsWith("--", StringComparison.Ordinal) || index + 1 >= arguments.Length)
            {
                throw new ArgumentException($"Invalid argument: {arguments[index]}");
            }

            result[arguments[index][2..]] = arguments[++index];
        }

        return result;
    }

    public static string FindRepositoryRoot(string startPath)
    {
        var directory = new DirectoryInfo(startPath);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Docs", "FORMAT.md"))
                && Directory.Exists(Path.Combine(directory.FullName, "macOS", "BundlePack"))
                && Directory.Exists(Path.Combine(directory.FullName, "Windows", "BundlePack.Core")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Could not locate the BundlePack repository root.");
    }

    public static void Require(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }

    private static void WriteEntry(
        ZipArchive archive,
        string path,
        byte[] data,
        CompressionLevel compressionLevel)
    {
        var entry = archive.CreateEntry(path, compressionLevel);
        using var output = entry.Open();
        output.Write(data);
    }
}

internal sealed class ImmediateProgress<T>(Action<T> handler) : IProgress<T>
{
    public void Report(T value) => handler(value);
}
