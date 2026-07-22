using BundlePack.Core;
using static TestSupport;

internal static class ArchiveValidationScenarios
{
    public static async Task<string> RunAsync(string temporaryRoot, byte[] iconPng)
    {
        var unsafeArchivePath = Path.Combine(temporaryRoot, "unsafe-name.bundlepack");
        CreateUnsafeNameArchive(unsafeArchivePath, iconPng);
        try
        {
            _ = await BundlePackArchive.InspectAsync(unsafeArchivePath);
            throw new InvalidOperationException("A Windows-reserved archive path was accepted.");
        }
        catch (BundlePackException exception) when (exception.Error == BundlePackError.UnsafeEntry)
        {
            // Expected: every package must remain extractable on both supported platforms.
        }

        var manifestMismatchPath = Path.Combine(temporaryRoot, "manifest-mismatch.bundlepack");
        CreateTestArchive(manifestMismatchPath, iconPng, "[]", "payload/hello.txt", "unsafe"u8.ToArray());
        try
        {
            _ = await BundlePackArchive.InspectAsync(manifestMismatchPath);
            throw new InvalidOperationException("A manifest that disagrees with the payload was accepted.");
        }
        catch (BundlePackException exception) when (exception.Error == BundlePackError.InvalidManifest)
        {
            // Expected.
        }

        var invalidIconPath = Path.Combine(temporaryRoot, "invalid-icon.bundlepack");
        CreateTestArchive(
            invalidIconPath,
            "not a PNG"u8.ToArray(),
            "[{\"path\":\"hello.txt\",\"size\":6}]",
            "payload/hello.txt",
            "unsafe"u8.ToArray());
        try
        {
            _ = await BundlePackArchive.InspectAsync(invalidIconPath);
            throw new InvalidOperationException("A package with an invalid icon was accepted.");
        }
        catch (BundlePackException exception) when (exception.Error == BundlePackError.InvalidIcon)
        {
            // Expected.
        }

        var trailingDataPath = Path.Combine(temporaryRoot, "trailing-data.bundlepack");
        CreateTestArchive(
            trailingDataPath,
            iconPng,
            "[{\"path\":\"hello.txt\",\"size\":6}]",
            "payload/hello.txt",
            "unsafe"u8.ToArray());
        File.WriteAllBytes(
            trailingDataPath,
            File.ReadAllBytes(trailingDataPath).Concat("unexpected trailing data"u8.ToArray()).ToArray());
        try
        {
            _ = await BundlePackArchive.InspectAsync(trailingDataPath);
            throw new InvalidOperationException("A ZIP with data appended after its declared comment was accepted.");
        }
        catch (BundlePackException exception) when (exception.Error == BundlePackError.NotZip)
        {
            // Expected.
        }

        var unexpectedRootPath = Path.Combine(temporaryRoot, "unexpected-root.bundlepack");
        CreateTestArchive(
            unexpectedRootPath,
            iconPng,
            "[{\"path\":\"hello.txt\",\"size\":6}]",
            "payload/hello.txt",
            "unsafe"u8.ToArray(),
            extraRootEntryPath: "note.txt");
        try
        {
            _ = await BundlePackArchive.InspectAsync(unexpectedRootPath);
            throw new InvalidOperationException("A file outside the BundlePack root layout was accepted.");
        }
        catch (BundlePackException exception) when (exception.Error == BundlePackError.InvalidEntry)
        {
            // Expected.
        }

        var crcMismatchPath = Path.Combine(temporaryRoot, "crc-mismatch.bundlepack");
        CreateTestArchive(
            crcMismatchPath,
            iconPng,
            "[{\"path\":\"hello.txt\",\"size\":6}]",
            "payload/hello.txt",
            "unsafe"u8.ToArray());
        TamperStoredPayload(crcMismatchPath, "unsafe"u8, "vnsafe"u8);
        using (var crcPackage = await BundlePackService.OpenAsync(crcMismatchPath))
        {
            try
            {
                _ = await BundlePackService.ExtractAsync(crcPackage, Path.Combine(temporaryRoot, "crc-output"));
                throw new InvalidOperationException("A payload with an invalid CRC was extracted.");
            }
            catch (BundlePackException exception) when (exception.Error == BundlePackError.InvalidEntry)
            {
                // Expected.
            }
        }

        var unsafeTitlePath = Path.Combine(temporaryRoot, "unsafe-title.bundlepack");
        CreateTestArchive(
            unsafeTitlePath,
            iconPng,
            "[{\"path\":\"hello.txt\",\"size\":6}]",
            "payload/hello.txt",
            "unsafe"u8.ToArray(),
            title: "CON");
        using (var unsafeTitlePackage = await BundlePackService.OpenAsync(unsafeTitlePath))
        {
            var extractionParent = Path.Combine(temporaryRoot, "safe-title-output");
            var extracted = await BundlePackService.ExtractAsync(unsafeTitlePackage, extractionParent);
            Require(
                string.Equals(Path.GetDirectoryName(extracted), extractionParent, StringComparison.OrdinalIgnoreCase)
                    && string.Equals(Path.GetFileName(extracted), "BundlePack", StringComparison.OrdinalIgnoreCase),
                "A Windows-reserved package title was used as the extraction folder name.");
        }

        return unsafeTitlePath;
    }
}
